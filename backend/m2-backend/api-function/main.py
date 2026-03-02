"""
Cloud Function (2nd gen, HTTP trigger) — PostHarvest REST API.

Provides supplemental endpoints for M4's Flutter app and general data access.

Endpoints
---------
GET  /warehouses                                      → list all warehouses + latest status
GET  /warehouse/{id}/summary                          → aggregated stats for one warehouse
GET  /warehouse/{id}/export?hours=24                  → CSV export of readings
POST /alerts/{warehouseId}/{alertId}/acknowledge       → mark an alert as acknowledged
GET  /health                                          → health check

Firestore paths used (consistent with M1's init_firestore.py):
    warehouses/{warehouseId}                  – warehouse metadata
    warehouses/{warehouseId}/latest/current   – real-time latest reading
    warehouses/{warehouseId}/readings         – historical sensor readings
    warehouses/{warehouseId}/alerts           – alert documents

Field names in Firestore (camelCase, set by M1's predict-spoilage):
    temperature, humidity, co2, gasLevel, riskScore, riskLevel,
    daysToSpoilage, recommendation, estimatedLossInr, timestamp, imageUrl
"""

import csv
import io
import json
from datetime import datetime, timedelta

import functions_framework
from google.cloud import firestore

db = firestore.Client()

# ═══════════════════════════════════════════════════════════════════════
# CORS HELPER
# ═══════════════════════════════════════════════════════════════════════

_CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "3600",
}


def _cors_preflight():
    """Handle CORS pre-flight OPTIONS request."""
    return ("", 204, _CORS)


def _json_response(body, status=200):
    """Return a JSON response with CORS headers."""
    return (json.dumps(body, default=str), status, {**_CORS, "Content-Type": "application/json"})


def _csv_response(content: str, filename: str):
    """Return a CSV file download response with CORS headers."""
    return (
        content,
        200,
        {
            **_CORS,
            "Content-Type": "text/csv",
            "Content-Disposition": f'attachment; filename="{filename}"',
        },
    )


# ═══════════════════════════════════════════════════════════════════════
# ENDPOINT HANDLERS
# ═══════════════════════════════════════════════════════════════════════

def _list_warehouses() -> tuple:
    """GET /warehouses — all warehouses with their latest status.

    Returns a JSON array. Each item includes:
      - id, name, commodityType, location (lat/lng dict)
      - latest: the latest/current subdocument (real-time sensor + prediction)
      - unacknowledged_alerts: count of alerts not yet acknowledged by farmer
    """
    warehouses = []
    for doc in db.collection("warehouses").stream():
        wh = doc.to_dict()
        wh["id"] = doc.id

        # Fetch latest/current subdocument (written by M1's predict-spoilage)
        latest_ref = doc.reference.collection("latest").document("current")
        latest_doc = latest_ref.get()
        if latest_doc.exists:
            latest_data = latest_doc.to_dict()
            # Convert Firestore Timestamp to ISO string for JSON serialisation
            if "timestamp" in latest_data and hasattr(latest_data["timestamp"], "isoformat"):
                latest_data["timestamp"] = latest_data["timestamp"].isoformat()
            wh["latest"] = latest_data
        else:
            wh["latest"] = None

        # Count unacknowledged alerts
        alerts_query = (
            doc.reference.collection("alerts")
            .where("acknowledged", "==", False)
        )
        wh["unacknowledged_alerts"] = sum(1 for _ in alerts_query.stream())

        # Convert GeoPoint → dict (not JSON serialisable natively)
        if "location" in wh and hasattr(wh["location"], "latitude"):
            wh["location"] = {
                "latitude": wh["location"].latitude,
                "longitude": wh["location"].longitude,
            }

        # Convert any remaining Timestamp fields
        if "createdAt" in wh and hasattr(wh["createdAt"], "isoformat"):
            wh["createdAt"] = wh["createdAt"].isoformat()

        warehouses.append(wh)

    return _json_response(warehouses)


def _warehouse_summary(warehouse_id: str) -> tuple:
    """GET /warehouse/{id}/summary — aggregated stats over last 24 hours.

    Returns avg/min/max for temperature, humidity, riskScore, plus alert counts.
    Field names in the response use snake_case for REST convention; Firestore
    fields are camelCase (as written by M1).
    """
    wh_ref = db.collection("warehouses").document(warehouse_id)
    wh_doc = wh_ref.get()
    if not wh_doc.exists:
        return _json_response({"error": f"Warehouse '{warehouse_id}' not found."}, 404)

    # Query readings from last 24 hours
    since = datetime.utcnow() - timedelta(hours=24)
    readings = list(
        wh_ref.collection("readings")
        .where("timestamp", ">=", since)
        .order_by("timestamp")
        .stream()
    )

    if not readings:
        return _json_response({
            "warehouse_id": warehouse_id,
            "readings_count": 0,
            "message": "No readings in the last 24 hours.",
        })

    temps, hums, risks, days_list = [], [], [], []
    for r in readings:
        d = r.to_dict()
        temps.append(d.get("temperature", 0))
        hums.append(d.get("humidity", 0))
        risks.append(d.get("riskScore", 0))
        if "daysToSpoilage" in d:
            days_list.append(d["daysToSpoilage"])

    # Count alerts
    total_alerts = sum(1 for _ in wh_ref.collection("alerts").stream())
    unack_alerts = sum(
        1 for _ in wh_ref.collection("alerts")
        .where("acknowledged", "==", False)
        .stream()
    )

    summary = {
        "warehouse_id":       warehouse_id,
        "commodity_type":     wh_doc.to_dict().get("commodityType", "unknown"),
        "readings_count":     len(readings),
        "period_hours":       24,
        "temperature": {
            "avg": round(sum(temps) / len(temps), 2),
            "min": round(min(temps), 2),
            "max": round(max(temps), 2),
        },
        "humidity": {
            "avg": round(sum(hums) / len(hums), 2),
            "min": round(min(hums), 2),
            "max": round(max(hums), 2),
        },
        "risk_score": {
            "avg": round(sum(risks) / len(risks), 2),
            "min": round(min(risks), 2),
            "max": round(max(risks), 2),
        },
        "days_to_spoilage_latest": round(days_list[-1], 2) if days_list else None,
        "total_alerts":         total_alerts,
        "unacknowledged_alerts": unack_alerts,
    }

    return _json_response(summary)


def _export_readings(warehouse_id: str, hours: int = 24) -> tuple:
    """GET /warehouse/{id}/export?hours=N — CSV export of readings.

    Column names use camelCase to match Firestore field names (M1 schema).
    """
    wh_ref = db.collection("warehouses").document(warehouse_id)
    since = datetime.utcnow() - timedelta(hours=hours)

    readings = list(
        wh_ref.collection("readings")
        .where("timestamp", ">=", since)
        .order_by("timestamp")
        .stream()
    )

    if not readings:
        return _json_response({"error": "No readings to export."}, 404)

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "timestamp", "temperature", "humidity", "co2", "gasLevel",
        "riskScore", "riskLevel", "daysToSpoilage", "recommendation",
    ])

    for r in readings:
        d = r.to_dict()
        ts = d.get("timestamp")
        if hasattr(ts, "isoformat"):
            ts = ts.isoformat()
        writer.writerow([
            ts,
            d.get("temperature", ""),
            d.get("humidity", ""),
            d.get("co2", ""),
            d.get("gasLevel", ""),
            d.get("riskScore", ""),
            d.get("riskLevel", ""),
            d.get("daysToSpoilage", ""),
            d.get("recommendation", ""),
        ])

    filename = f"{warehouse_id}_readings_{hours}h.csv"
    return _csv_response(output.getvalue(), filename)


def _acknowledge_alert(warehouse_id: str, alert_id: str) -> tuple:
    """POST /alerts/{warehouseId}/{alertId}/acknowledge — mark as acknowledged.

    This endpoint is called by M4's Flutter app when a user taps the
    "Acknowledge" button on an alert card.  The Firestore security rules
    also allow the Flutter app to update ONLY the 'acknowledged' field
    directly, but using this API is simpler for the app.
    """
    alert_ref = (
        db.collection("warehouses")
        .document(warehouse_id)
        .collection("alerts")
        .document(alert_id)
    )
    alert_doc = alert_ref.get()
    if not alert_doc.exists:
        return _json_response({"error": "Alert not found."}, 404)

    alert_ref.update({"acknowledged": True})
    return _json_response({"status": "acknowledged", "alert_id": alert_id})


def _health() -> tuple:
    """GET /health — simple health check for monitoring and integration tests."""
    return _json_response({"status": "healthy", "timestamp": datetime.utcnow().isoformat()})


# ═══════════════════════════════════════════════════════════════════════
# ROUTER
# ═══════════════════════════════════════════════════════════════════════

@functions_framework.http
def api_handler(request):
    """Single Cloud Function with lightweight path-based routing.

    The Cloud Function URL becomes the base, and the path after it
    determines the endpoint:
        https://<REGION>-<PROJECT>.cloudfunctions.net/postharvest-api/warehouses
    """

    if request.method == "OPTIONS":
        return _cors_preflight()

    path   = request.path.rstrip("/")
    method = request.method

    # GET /health
    if path == "/health":
        return _health()

    # GET /warehouses
    if path == "/warehouses" and method == "GET":
        return _list_warehouses()

    # Parse path segments for parameterised routes
    parts = path.split("/")

    # GET /warehouse/{id}/summary
    if len(parts) == 4 and parts[1] == "warehouse" and parts[3] == "summary" and method == "GET":
        return _warehouse_summary(parts[2])

    # GET /warehouse/{id}/export?hours=24
    if len(parts) == 4 and parts[1] == "warehouse" and parts[3] == "export" and method == "GET":
        hours = int(request.args.get("hours", 24))
        return _export_readings(parts[2], hours)

    # POST /alerts/{warehouseId}/{alertId}/acknowledge
    if (
        len(parts) == 5
        and parts[1] == "alerts"
        and parts[4] == "acknowledge"
        and method == "POST"
    ):
        return _acknowledge_alert(parts[2], parts[3])

    return _json_response({"error": "Not found", "path": path}, 404)
