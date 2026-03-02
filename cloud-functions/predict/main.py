import json
import os
import pickle
from datetime import datetime

import firebase_admin
import functions_framework
import numpy as np
from firebase_admin import messaging
from google.cloud import bigquery, firestore

# ═══════════════════════════════════════════════════════════════════════
# GLOBAL SCOPE — loaded ONCE on cold start, reused on warm invocations
# ═══════════════════════════════════════════════════════════════════════

_DIR = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(_DIR, "risk_score_model.pkl"), "rb") as f:
    RISK_MODEL = pickle.load(f)       # XGBoost regressor → risk_score 0-100

with open(os.path.join(_DIR, "spoilage_regressor.pkl"), "rb") as f:
    REGRESSOR = pickle.load(f)        # XGBoost regressor → days_to_spoilage

with open(os.path.join(_DIR, "model_metadata.pkl"), "rb") as f:
    METADATA = pickle.load(f)

with open(os.path.join(_DIR, "commodity_thresholds.json"), "r") as f:
    THRESHOLDS = json.load(f)

# Firebase / GCP clients (connection pooling across warm calls)
if not firebase_admin._apps:
    firebase_admin.initialize_app()

db = firestore.Client()
bq = bigquery.Client()

PROJECT_ID = os.environ.get("GCP_PROJECT", "postharvest-hack")
BQ_TABLE = f"{PROJECT_ID}.postharvest.sensor_readings"

RISK_LABELS = ["low", "medium", "high", "critical"]


# ═══════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════

def _build_feature_vector(data: dict) -> np.ndarray:
    """Map incoming sensor JSON to the feature vector expected by the model."""
    commodity = data.get("commodity_type", "tomato")
    commodity_encoder = METADATA["label_encoders"]["commodity"]
    commodity_encoded = commodity_encoder.transform([commodity])[0]

    temp = data["temperature"]
    hum = data["humidity"]

    # Vapor Pressure Deficit (Magnus formula)
    svp = 0.6108 * np.exp(17.27 * temp / (temp + 237.3))
    avp = svp * (hum / 100)
    vpd = svp - avp

    # Deviations from commodity-specific optimal ranges
    OPTIMAL_TEMP_MID = {
        "tomato": 13.5, "potato": 4.5, "banana": 13.5,
        "rice": 17.5, "onion": 1.0,
    }
    OPTIMAL_RH_MID = {
        "tomato": 90.0, "potato": 96.5, "banana": 92.5,
        "rice": 57.5, "onion": 67.5,
    }
    temp_deviation = abs(temp - OPTIMAL_TEMP_MID.get(commodity, 13.5))
    humidity_deviation = abs(hum - OPTIMAL_RH_MID.get(commodity, 90.0))
    hours = data.get("hours_in_storage", 0)
    temp_hours_stress = temp_deviation * hours

    return np.array([[
        temp,
        hum,
        data.get("co2", 400),
        data.get("gas_level", 0),
        hours,
        commodity_encoded,
        vpd,
        temp_deviation,
        humidity_deviation,
        temp_hours_stress,
    ]])


def _generate_recommendation(data: dict, risk_level: str) -> str:
    """Return an actionable recommendation string based on the dominant risk factor."""
    commodity = data.get("commodity_type", "tomato")
    th = THRESHOLDS.get(commodity, THRESHOLDS["tomato"])
    recs = th.get("recommendations", {})

    temp = data["temperature"]
    hum = data["humidity"]
    gas = data.get("gas_level", 0)

    parts = []
    if temp > th["optimal_temp_max"]:
        parts.append(recs.get("temperature_high", "Reduce temperature."))
    if hum < th["optimal_rh_min"]:
        parts.append(recs.get("humidity_low", "Increase humidity."))
    elif hum > th["optimal_rh_max"]:
        parts.append(recs.get("humidity_high", "Reduce humidity."))
    if gas > 200:
        parts.append(recs.get("gas_spike", "Ventilate the storage area."))

    if not parts:
        return "Conditions are within the optimal range. No action required."
    return " ".join(parts)


def _estimate_loss_inr(
    commodity: str, days_to_spoilage: float, quantity_kg: float = 1000
) -> float:
    """Approximate monetary loss if current conditions persist."""
    th = THRESHOLDS.get(commodity, THRESHOLDS["tomato"])
    price = th.get("price_per_kg_inr", 30)
    optimal_days = th.get("shelf_life_days_optimal", 14)
    if optimal_days == 0:
        return 0.0
    fraction_lost = max(0, 1 - days_to_spoilage / optimal_days)
    return round(fraction_lost * quantity_kg * price, 2)


# ═══════════════════════════════════════════════════════════════════════
# HTTP HANDLER
# ═══════════════════════════════════════════════════════════════════════

@functions_framework.http
def predict_handler(request):
    """Main entry point.  Accepts POST with sensor JSON, returns prediction."""

    # ── CORS pre-flight ───────────────────────────────────────────────
    if request.method == "OPTIONS":
        return (
            "",
            204,
            {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST",
                "Access-Control-Allow-Headers": "Content-Type",
                "Access-Control-Max-Age": "3600",
            },
        )

    headers = {"Access-Control-Allow-Origin": "*"}

    # ── Parse input ───────────────────────────────────────────────────
    data = request.get_json(silent=True)
    if not data or "temperature" not in data or "humidity" not in data:
        return ({"error": "Invalid payload. Required: temperature, humidity."}, 400, headers)

    warehouse_id = data.get("warehouse_id", "wh001")
    commodity    = data.get("commodity_type", "tomato")
    timestamp    = datetime.utcnow()

    # ── ML inference (two-stage: score regressor → bin) ───────────────
    features = _build_feature_vector(data)

    # Risk score: continuous 0-100 from the regressor
    risk_score_raw = float(RISK_MODEL.predict(features)[0])
    risk_score = round(max(0.0, min(100.0, risk_score_raw)), 2)

    # Risk level: bin the predicted score
    if risk_score <= 25:
        risk_level = "low"
    elif risk_score <= 50:
        risk_level = "medium"
    elif risk_score <= 75:
        risk_level = "high"
    else:
        risk_level = "critical"

    # Days to spoilage: separate regressor
    days_to_spoilage = round(float(REGRESSOR.predict(features)[0]), 2)
    days_to_spoilage = max(days_to_spoilage, 0)

    recommendation  = _generate_recommendation(data, risk_level)
    estimated_loss  = _estimate_loss_inr(commodity, days_to_spoilage)

    # ── Firestore: latest document (real-time for Flutter) ────────────
    wh_ref  = db.collection("warehouses").document(warehouse_id)
    reading = {
        "temperature":      data["temperature"],
        "humidity":         data["humidity"],
        "co2":              data.get("co2", 400),
        "gasLevel":         data.get("gas_level", 0),
        "riskScore":        risk_score,
        "riskLevel":        risk_level,
        "daysToSpoilage":   days_to_spoilage,
        "recommendation":   recommendation,
        "estimatedLossInr": estimated_loss,
        "timestamp":        timestamp,
        "imageUrl":         data.get("image_url", ""),
    }
    wh_ref.collection("latest").document("current").set(reading, merge=True)

    # ── Firestore: readings subcollection (history for charts) ────────
    wh_ref.collection("readings").add({**reading, "timestamp": timestamp})

    # ── Firestore: predictions subcollection ──────────────────────────
    # Confidence: distance from nearest boundary (further = more certain)
    boundaries = [0, 25, 50, 75, 100]
    min_boundary_dist = min(abs(risk_score - b) for b in boundaries)
    confidence = round(min(min_boundary_dist / 12.5 * 100, 100.0), 2)

    wh_ref.collection("predictions").add({
        "riskScore":        risk_score,
        "riskLevel":        risk_level,
        "daysToSpoilage":   days_to_spoilage,
        "confidence":       confidence,
        "modelVersion":     METADATA.get("model_version", "4.0"),
        "timestamp":        timestamp,
    })

    # ── BigQuery: streaming insert (≈ $0.005/month at hackathon scale) ─
    bq_row = {
        "warehouse_id":     warehouse_id,
        "temperature":      data["temperature"],
        "humidity":         data["humidity"],
        "co2":              data.get("co2", 400),
        "gas_level":        data.get("gas_level", 0),
        "risk_score":       risk_score,
        "risk_level":       risk_level,
        "commodity_type":   commodity,
        "days_to_spoilage": days_to_spoilage,
        "timestamp":        timestamp.isoformat(),
    }
    try:
        bq.insert_rows_json(BQ_TABLE, [bq_row])
    except Exception as e:
        print(f"[BigQuery insert error] {e}")

    # ── FCM alert on high / critical risk ─────────────────────────────
    if risk_level in ("high", "critical"):
        alert_doc = {
            "type":         f"{risk_level}_risk",
            "severity":     "critical" if risk_level == "critical" else "warning",
            "message":      (
                f"Spoilage risk is {risk_level.upper()}! "
                f"Temp {data['temperature']} °C · Humidity {data['humidity']} % · "
                f"Est. shelf life {days_to_spoilage} days. "
                f"{recommendation}"
            ),
            "timestamp":    timestamp,
            "acknowledged": False,
        }
        wh_ref.collection("alerts").add(alert_doc)

        try:
            fcm_msg = messaging.Message(
                notification=messaging.Notification(
                    title=f"⚠️ {risk_level.upper()} Spoilage Risk — {commodity.title()}",
                    body=alert_doc["message"],
                ),
                data={
                    "warehouse_id": warehouse_id,
                    "risk_level":   risk_level,
                    "risk_score":   str(risk_score),
                },
                topic=f"warehouse_{warehouse_id}",
                android=messaging.AndroidConfig(
                    priority="high",
                    notification=messaging.AndroidNotification(
                        sound="default",
                        channel_id="spoilage_alerts",
                    ),
                ),
            )
            messaging.send(fcm_msg)
        except Exception as e:
            print(f"[FCM error] {e}")

    # ── Response ──────────────────────────────────────────────────────
    return (
        {
            "status":           "ok",
            "risk_level":       risk_level,
            "risk_score":       risk_score,
            "days_to_spoilage": days_to_spoilage,
            "recommendation":   recommendation,
            "estimated_loss_inr": estimated_loss,
            "timestamp":        timestamp.isoformat(),
        },
        200,
        headers,
    )