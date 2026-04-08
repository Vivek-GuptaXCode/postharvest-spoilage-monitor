"""
PostHarvest — Firebase Receiver Dashboard (Flask)
REST API to view Firestore data from a browser or curl.

READ-ONLY: This code never writes to Firestore.

Endpoints:
  /                            — Health check
  /warehouse                   — Warehouse info
  /warehouse/aggregate         — Warehouse-level aggregate
  /zones                       — All zones latest data
  /zone/<zone_id>              — Single zone latest
  /zone/<zone_id>/history      — Zone reading history (default 10)
  /zone/<zone_id>/history/<n>  — Zone reading history (limit n)
  /alerts                      — Recent alerts (default 20)
  /alerts/<n>                  — Recent alerts (limit n)
  /readings                    — Warehouse-level readings (default 20)
  /readings/<n>                — Warehouse-level readings (limit n)
  /dashboard                   — Full summary of all zones
"""

from flask import Flask, jsonify
import firebase_admin
from firebase_admin import credentials, firestore
import os
from datetime import datetime

app = Flask(__name__)

# ══════════════════════════════════════════════════════════════
#  CONFIG
# ══════════════════════════════════════════════════════════════

WAREHOUSE_ID = "wh001"

ZONES = [
    "zone-A", "zone-B", "zone-C", "zone-D", "zone-E",
    "zone-F", "zone-G", "zone-H", "zone-I", "zone-J",
]

_DIR = os.path.dirname(os.path.abspath(__file__))
KEY_PATH = os.path.join(
    _DIR, "..", "postharvest-hack-firebase-adminsdk-fbsvc-cedb52b07e.json"
)

# ══════════════════════════════════════════════════════════════
#  FIREBASE INIT
# ══════════════════════════════════════════════════════════════

cred = credentials.Certificate(KEY_PATH)
firebase_admin.initialize_app(cred)
db = firestore.client()


# ══════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════

def _serialize_doc(data: dict) -> dict:
    """Convert Firestore doc to JSON-safe dict (timestamps → ISO strings)."""
    out = {}
    for k, v in data.items():
        if hasattr(v, "isoformat"):
            out[k] = v.isoformat()
        elif hasattr(v, "latitude"):  # GeoPoint
            out[k] = {"lat": v.latitude, "lng": v.longitude}
        else:
            out[k] = v
    return out


# ══════════════════════════════════════════════════════════════
#  ENDPOINTS (ALL READ-ONLY)
# ══════════════════════════════════════════════════════════════

@app.route("/")
def health():
    return jsonify({
        "service": "PostHarvest Firebase Receiver Dashboard",
        "warehouse": WAREHOUSE_ID,
        "zones": len(ZONES),
        "mode": "READ-ONLY",
        "data_source": "Firestore (Cloud Function writes after AES decrypt + ML)",
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    })


@app.route("/warehouse")
def get_warehouse():
    """GET /warehouse — warehouse document info."""
    doc = db.collection("warehouses").document(WAREHOUSE_ID).get()
    if doc.exists:
        return jsonify(_serialize_doc(doc.to_dict()))
    return jsonify({"error": "Warehouse not found"}), 404


@app.route("/warehouse/aggregate")
def get_warehouse_aggregate():
    """GET /warehouse/aggregate — warehouse-level latest aggregate."""
    doc = (
        db.collection("warehouses")
        .document(WAREHOUSE_ID)
        .collection("latest")
        .document("current")
        .get()
    )
    if doc.exists:
        return jsonify(_serialize_doc(doc.to_dict()))
    return jsonify({"error": "No aggregate data"}), 404


@app.route("/zones")
def get_all_zones():
    """GET /zones — latest data for all zones."""
    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    result = {}

    for zone_id in ZONES:
        doc_ref = (
            wh_ref.collection("zones")
            .document(zone_id)
            .collection("latest")
            .document("current")
        )
        doc = doc_ref.get()

        if doc.exists:
            result[zone_id] = _serialize_doc(doc.to_dict())
        else:
            result[zone_id] = {"status": "no data"}

    return jsonify({
        "warehouse_id": WAREHOUSE_ID,
        "total_zones": len(result),
        "zones": result,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    })


@app.route("/zone/<zone_id>")
def get_zone(zone_id):
    """GET /zone/<zone_id> — latest data for one zone."""
    doc_ref = (
        db.collection("warehouses")
        .document(WAREHOUSE_ID)
        .collection("zones")
        .document(zone_id)
        .collection("latest")
        .document("current")
    )
    doc = doc_ref.get()
    if doc.exists:
        return jsonify(_serialize_doc(doc.to_dict()))
    return jsonify({"error": f"No data for {zone_id}"}), 404


@app.route("/zone/<zone_id>/history")
@app.route("/zone/<zone_id>/history/<int:limit>")
def get_zone_history(zone_id, limit=10):
    """GET /zone/<zone_id>/history[/<limit>] — zone reading history."""
    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    readings_ref = (
        wh_ref.collection("zones")
        .document(zone_id)
        .collection("readings")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit)
    )

    docs = readings_ref.stream()
    history = [_serialize_doc(doc.to_dict()) for doc in docs]

    return jsonify({
        "zone_id": zone_id,
        "count": len(history),
        "history": history,
    })


@app.route("/alerts")
@app.route("/alerts/<int:limit>")
def get_alerts(limit=20):
    """GET /alerts[/<limit>] — recent alerts."""
    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    alerts_ref = (
        wh_ref.collection("alerts")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit)
    )

    docs = alerts_ref.stream()
    alert_list = [_serialize_doc(doc.to_dict()) for doc in docs]

    return jsonify({
        "warehouse_id": WAREHOUSE_ID,
        "total": len(alert_list),
        "alerts": alert_list,
    })


@app.route("/readings")
@app.route("/readings/<int:limit>")
def get_readings(limit=20):
    """GET /readings[/<limit>] — warehouse-level readings."""
    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    readings_ref = (
        wh_ref.collection("readings")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit)
    )

    docs = readings_ref.stream()
    reading_list = [_serialize_doc(doc.to_dict()) for doc in docs]

    return jsonify({
        "warehouse_id": WAREHOUSE_ID,
        "total": len(reading_list),
        "readings": reading_list,
    })


@app.route("/dashboard")
def dashboard():
    """GET /dashboard — full summary of all zones."""
    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    summary = []

    for zone_id in ZONES:
        doc_ref = (
            wh_ref.collection("zones")
            .document(zone_id)
            .collection("latest")
            .document("current")
        )
        doc = doc_ref.get()

        if doc.exists:
            d = doc.to_dict()
            summary.append({
                "zone":         zone_id,
                "commodity":    d.get("commodityType"),
                "temperature":  d.get("temperature"),
                "humidity":     d.get("humidity"),
                "co2":          d.get("co2"),
                "gas_level":    d.get("gasLevel"),
                "risk_score":   d.get("riskScore"),
                "risk_level":   d.get("riskLevel"),
                "days_left":    d.get("daysToSpoilage"),
                "loss_inr":     d.get("estimatedLossInr"),
                "recommendation": d.get("recommendation"),
            })
        else:
            summary.append({"zone": zone_id, "status": "no data"})

    # Warehouse aggregate
    agg_doc = wh_ref.collection("latest").document("current").get()
    aggregate = _serialize_doc(agg_doc.to_dict()) if agg_doc.exists else None

    return jsonify({
        "warehouse": WAREHOUSE_ID,
        "total_zones": len(summary),
        "aggregate": aggregate,
        "zones": summary,
        "data_source": "Firestore (plaintext — decrypted by Cloud Function)",
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    })


# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print(f"\n{'=' * 60}")
    print(f"  PostHarvest — Firebase Receiver Dashboard")
    print(f"  Reads data from Firestore (READ-ONLY)")
    print(f"{'=' * 60}")
    print(f"  Warehouse  : {WAREHOUSE_ID}")
    print(f"  Port       : 5001")
    print(f"  Mode       : READ-ONLY (no Firestore writes)")
    print(f"{'=' * 60}")
    print(f"  Endpoints:")
    print(f"    /                            — Health")
    print(f"    /warehouse                   — Warehouse info")
    print(f"    /warehouse/aggregate         — Aggregate latest")
    print(f"    /zones                       — All zones (latest)")
    print(f"    /zone/zone-A                 — Single zone")
    print(f"    /zone/zone-A/history         — Zone history")
    print(f"    /zone/zone-A/history/20      — Zone history (limit)")
    print(f"    /alerts                      — Alerts")
    print(f"    /readings                    — Warehouse readings")
    print(f"    /dashboard                   — Full summary")
    print(f"{'=' * 60}\n")

    app.run(host="0.0.0.0", port=5001, debug=False)
