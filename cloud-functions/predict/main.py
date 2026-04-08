import json
import os
import pickle
import base64
from datetime import datetime

import firebase_admin
import functions_framework
import numpy as np
from firebase_admin import messaging
from google.cloud import bigquery, firestore

from aes_decrypt import decrypt_aes128_cbc
from anomaly_detector import detect_anomalies
from crypto_config import AES_128_KEY

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

# Try to import generated protobuf stubs (optional — falls back to JSON)
try:
    from generated import sensor_pb2
    PROTOBUF_AVAILABLE = True
    print("[Init] Protobuf stubs loaded successfully")
except ImportError:
    PROTOBUF_AVAILABLE = False
    print("[Init] Protobuf stubs not found — encrypted mode will use JSON fallback")


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
# DECRYPTION
# ═══════════════════════════════════════════════════════════════════════

def _decrypt_batch(data: dict) -> list[dict]:
    """Decrypt AES-128-CBC encrypted protobuf payload.

    Input: {"iv": "<base64>", "ciphertext": "<base64>"}
    Output: list of dict readings
    """
    iv_b64 = data.get("iv", "")
    ct_b64 = data.get("ciphertext", "")

    if not iv_b64 or not ct_b64:
        raise ValueError("Missing 'iv' or 'ciphertext' in encrypted payload")

    iv = base64.b64decode(iv_b64)
    ciphertext = base64.b64decode(ct_b64)

    print(f"[Decrypt] IV: {len(iv)} bytes, Ciphertext: {len(ciphertext)} bytes")

    plaintext = decrypt_aes128_cbc(AES_128_KEY, iv, ciphertext)

    print(f"[Decrypt] Decrypted: {len(plaintext)} bytes")

    # Try protobuf first, then fall back to JSON
    if PROTOBUF_AVAILABLE:
        try:
            batch = sensor_pb2.SensorBatch()
            batch.ParseFromString(plaintext)
            if len(batch.readings) > 0:
                readings = []
                for sample in batch.readings:
                    readings.append({
                        "temperature": round(float(sample.temperature), 1),
                        "humidity": round(float(sample.humidity), 1),
                        "gas_level": round(float(sample.gas_level), 1),
                        "co2": round(float(sample.co2), 1),
                        "sample_offset_ms": int(sample.sample_offset_ms),
                    })
                print(f"[Decrypt] Parsed as protobuf: {len(readings)} readings")
                return readings
        except Exception as proto_err:
            print(f"[Decrypt] Protobuf parse failed ({proto_err}), trying JSON fallback")

    # Fallback: treat decrypted plaintext as JSON
    try:
        readings = json.loads(plaintext.decode("utf-8"))
        print(f"[Decrypt] Parsed as JSON: {len(readings)} readings")
        return readings
    except (json.JSONDecodeError, UnicodeDecodeError) as json_err:
        raise ValueError(f"Cannot parse decrypted payload as protobuf or JSON: {json_err}")


# ═══════════════════════════════════════════════════════════════════════
# SINGLE READING PROCESSOR (zone-aware)
# ═══════════════════════════════════════════════════════════════════════

def _process_single_reading(data: dict, warehouse_id: str, zone_id: str,
                             commodity: str, timestamp) -> dict:
    """Process one reading: anomaly check → ML inference → zone-aware Firestore writes."""

    # ── Anomaly detection (before ML inference) ───────────────────────
    anomaly = detect_anomalies(data, commodity, THRESHOLDS)
    is_anomalous   = anomaly["is_anomalous"]
    anomaly_score  = anomaly["anomaly_score"]
    anomaly_flags  = anomaly["anomaly_flags"]

    if is_anomalous:
        print(f"[Anomaly] score={anomaly_score} flags={anomaly_flags} "
              f"zone={zone_id} temp={data.get('temperature')} "
              f"hum={data.get('humidity')} co2={data.get('co2')} "
              f"gas={data.get('gas_level')}")

    # If physically impossible (score=1.0), skip ML — garbage in = garbage out
    if anomaly_score >= 1.0:
        risk_score = 0.0
        risk_level = "unknown"
        days_to_spoilage = -1.0
        recommendation = ("ANOMALY: Sensor data appears corrupted. "
                          "Check IoT device hardware and connectivity.")
        estimated_loss = 0.0
    else:
        features = _build_feature_vector(data)

        # Risk score: continuous 0-100
        risk_score_raw = float(RISK_MODEL.predict(features)[0])
        risk_score = round(max(0.0, min(100.0, risk_score_raw)), 2)

        # Risk level: bin the score
        if risk_score <= 25:    risk_level = "low"
        elif risk_score <= 50:  risk_level = "medium"
        elif risk_score <= 75:  risk_level = "high"
        else:                   risk_level = "critical"

        # Days to spoilage
        days_to_spoilage = round(float(REGRESSOR.predict(features)[0]), 2)
        days_to_spoilage = max(days_to_spoilage, 0)

        recommendation = _generate_recommendation(data, risk_level)
        estimated_loss = _estimate_loss_inr(commodity, days_to_spoilage)

    wh_ref = db.collection("warehouses").document(warehouse_id)

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
        "commodityType":    commodity,
        "zoneId":           zone_id,
        "timestamp":        timestamp,
        "imageUrl":         data.get("image_url", ""),
        "isAnomalous":      is_anomalous,
        "anomalyScore":     anomaly_score,
        "anomalyFlags":     anomaly_flags,
    }

    # ── Per-zone latest + readings (NEW) ──────────────────────────────
    zone_ref = wh_ref.collection("zones").document(zone_id)
    zone_ref.set({"name": zone_id, "commodityType": commodity}, merge=True)
    zone_ref.collection("latest").document("current").set(reading, merge=True)
    zone_ref.collection("readings").add({**reading, "timestamp": timestamp})

    # ── Backward-compatible warehouse-level readings ──────────────────
    wh_ref.collection("readings").add({**reading, "timestamp": timestamp})

    # ── Predictions subcollection ─────────────────────────────────────
    boundaries = [0, 25, 50, 75, 100]
    min_boundary_dist = min(abs(risk_score - b) for b in boundaries)
    confidence = round(min(min_boundary_dist / 12.5 * 100, 100.0), 2)

    wh_ref.collection("predictions").add({
        "riskScore":        risk_score,
        "riskLevel":        risk_level,
        "daysToSpoilage":   days_to_spoilage,
        "confidence":       confidence,
        "zoneId":           zone_id,
        "modelVersion":     METADATA.get("model_version", "4.0"),
        "timestamp":        timestamp,
    })

    # ── Anomaly alert (score >= 0.8 → likely corrupt IoT endpoint) ──
    if anomaly_score >= 0.8:
        anomaly_alert = {
            "type":         "anomaly",
            "severity":     "critical" if anomaly_score >= 1.0 else "warning",
            "zoneId":       zone_id,
            "message": (
                f"[{zone_id}] IoT payload anomaly detected (score {anomaly_score})! "
                f"Flags: {', '.join(anomaly_flags)}. "
                f"Temp {data['temperature']} °C · Humidity {data['humidity']} % · "
                f"CO₂ {data.get('co2', 400)} ppm · Gas {data.get('gas_level', 0)}. "
                f"Check sensor hardware and connectivity."
            ),
            "timestamp":    timestamp,
            "acknowledged": False,
        }
        wh_ref.collection("alerts").add(anomaly_alert)

        try:
            fcm_msg = messaging.Message(
                notification=messaging.Notification(
                    title=f"🔧 ANOMALY — {commodity.title()} [{zone_id}]",
                    body=anomaly_alert["message"],
                ),
                data={
                    "warehouse_id": warehouse_id,
                    "zone_id":      zone_id,
                    "anomaly_score": str(anomaly_score),
                    "anomaly_flags": ",".join(anomaly_flags),
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
            print(f"[FCM anomaly error] {e}")

    # ── Alerts on high/critical ───────────────────────────────────────
    if risk_level in ("high", "critical"):
        alert_doc = {
            "type":         f"{risk_level}_risk",
            "severity":     "critical" if risk_level == "critical" else "warning",
            "zoneId":       zone_id,
            "message": (
                f"[{zone_id}] Spoilage risk is {risk_level.upper()}! "
                f"Temp {data['temperature']} °C · Humidity {data['humidity']} % · "
                f"Est. shelf life {days_to_spoilage} days. {recommendation}"
            ),
            "timestamp":    timestamp,
            "acknowledged": False,
        }
        wh_ref.collection("alerts").add(alert_doc)

        try:
            fcm_msg = messaging.Message(
                notification=messaging.Notification(
                    title=f"⚠️ {risk_level.upper()} — {commodity.title()} [{zone_id}]",
                    body=alert_doc["message"],
                ),
                data={
                    "warehouse_id": warehouse_id,
                    "zone_id":      zone_id,
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

    return {
        "zone_id":            zone_id,
        "risk_level":         risk_level,
        "risk_score":         risk_score,
        "days_to_spoilage":   days_to_spoilage,
        "recommendation":     recommendation,
        "estimated_loss_inr": estimated_loss,
        "is_anomalous":       is_anomalous,
        "anomaly_score":      anomaly_score,
        "anomaly_flags":      anomaly_flags,
    }


def _update_warehouse_aggregate(warehouse_id: str, zone_results: list[dict]):
    """Compute warehouse-level aggregate from zone results and update latest."""
    if not zone_results:
        return

    wh_ref = db.collection("warehouses").document(warehouse_id)

    avg_risk   = sum(r["risk_score"] for r in zone_results) / len(zone_results)
    max_risk   = max(r["risk_score"] for r in zone_results)
    min_days   = min(r["days_to_spoilage"] for r in zone_results)
    total_loss = sum(r["estimated_loss_inr"] for r in zone_results)

    if max_risk <= 25:      agg_level = "low"
    elif max_risk <= 50:    agg_level = "medium"
    elif max_risk <= 75:    agg_level = "high"
    else:                   agg_level = "critical"

    wh_ref.collection("latest").document("current").set({
        "riskScore":        round(avg_risk, 2),
        "riskLevel":        agg_level,
        "maxRiskScore":     round(max_risk, 2),
        "daysToSpoilage":   round(min_days, 2),
        "estimatedLossInr": round(total_loss, 2),
        "zoneCount":        len(zone_results),
        "timestamp":        datetime.utcnow(),
    }, merge=True)


# ═══════════════════════════════════════════════════════════════════════
# HTTP HANDLER
# ═══════════════════════════════════════════════════════════════════════

@functions_framework.http
def predict_handler(request):
    """Accepts POST with encrypted batch, plaintext batch, or single reading."""

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
    if not data:
        return ({"error": "Invalid JSON payload."}, 400, headers)

    warehouse_id = data.get("warehouse_id", "wh001")
    zone_id      = data.get("zone_id", "zone-A")
    commodity    = data.get("commodity_type", "tomato")
    is_encrypted = data.get("encrypted", False)
    is_batch     = data.get("batch", False)
    timestamp    = datetime.utcnow()

    # ══════════════════════════════════════════════════════════════
    # MODE 1: Encrypted batch (AES-128-CBC + protobuf)
    # ══════════════════════════════════════════════════════════════
    if is_encrypted:
        try:
            readings_list = _decrypt_batch(data)
            print(f"[Encrypted] Decrypted {len(readings_list)} readings "
                  f"for {warehouse_id}/{zone_id}")
        except Exception as e:
            print(f"[Decrypt ERROR] {e}")
            return ({"error": f"Decryption failed: {str(e)}"}, 400, headers)

        if not readings_list:
            return ({"error": "Decrypted batch is empty"}, 400, headers)

        results = []
        bq_rows = []

        for i, reading in enumerate(readings_list):
            reading.setdefault("commodity_type", commodity)
            reading.setdefault("hours_in_storage", data.get("hours_in_storage", 0))

            if "temperature" not in reading or "humidity" not in reading:
                results.append({"index": i, "error": "Missing temperature or humidity"})
                continue

            result = _process_single_reading(
                reading, warehouse_id, zone_id, commodity, timestamp
            )
            result["index"] = i
            results.append(result)

            bq_rows.append({
                "warehouse_id":     warehouse_id,
                "zone_id":          zone_id,
                "temperature":      reading["temperature"],
                "humidity":         reading["humidity"],
                "co2":              reading.get("co2", 400),
                "gas_level":        reading.get("gas_level", 0),
                "risk_score":       result["risk_score"],
                "risk_level":       result["risk_level"],
                "commodity_type":   commodity,
                "days_to_spoilage": result["days_to_spoilage"],
                "timestamp":        timestamp.isoformat(),
            })

        if bq_rows:
            try:
                bq.insert_rows_json(BQ_TABLE, bq_rows)
            except Exception as e:
                print(f"[BigQuery batch insert error] {e}")

        successful = [r for r in results if "error" not in r]
        anomalies_detected = sum(1 for r in successful if r.get("is_anomalous"))
        _update_warehouse_aggregate(warehouse_id, successful)

        return ({
            "status":       "ok",
            "encrypted":    True,
            "batch_size":   len(readings_list),
            "processed":    len(successful),
            "anomalies_detected": anomalies_detected,
            "zone_id":      zone_id,
            "warehouse_id": warehouse_id,
            "results":      results,
            "timestamp":    timestamp.isoformat(),
        }, 200, headers)

    # ══════════════════════════════════════════════════════════════
    # MODE 2: Plaintext batch
    # ══════════════════════════════════════════════════════════════
    if is_batch and "readings" in data:
        readings_list = data["readings"]
        if not isinstance(readings_list, list) or len(readings_list) == 0:
            return ({"error": "Batch 'readings' must be a non-empty array."}, 400, headers)
        if len(readings_list) > 50:
            return ({"error": "Batch size exceeds maximum of 50."}, 400, headers)

        results = []
        bq_rows = []

        for i, reading in enumerate(readings_list):
            reading.setdefault("commodity_type", commodity)
            reading.setdefault("hours_in_storage", data.get("hours_in_storage", 0))

            if "temperature" not in reading or "humidity" not in reading:
                results.append({"index": i, "error": "Missing temperature or humidity"})
                continue

            result = _process_single_reading(
                reading, warehouse_id, zone_id, commodity, timestamp
            )
            result["index"] = i
            results.append(result)

            bq_rows.append({
                "warehouse_id":     warehouse_id,
                "zone_id":          zone_id,
                "temperature":      reading["temperature"],
                "humidity":         reading["humidity"],
                "co2":              reading.get("co2", 400),
                "gas_level":        reading.get("gas_level", 0),
                "risk_score":       result["risk_score"],
                "risk_level":       result["risk_level"],
                "commodity_type":   commodity,
                "days_to_spoilage": result["days_to_spoilage"],
                "timestamp":        timestamp.isoformat(),
            })

        if bq_rows:
            try:
                bq.insert_rows_json(BQ_TABLE, bq_rows)
            except Exception as e:
                print(f"[BigQuery batch error] {e}")

        successful = [r for r in results if "error" not in r]
        anomalies_detected = sum(1 for r in successful if r.get("is_anomalous"))
        _update_warehouse_aggregate(warehouse_id, successful)

        return ({
            "status":       "ok",
            "batch_size":   len(readings_list),
            "processed":    len(successful),
            "anomalies_detected": anomalies_detected,
            "zone_id":      zone_id,
            "warehouse_id": warehouse_id,
            "results":      results,
            "timestamp":    timestamp.isoformat(),
        }, 200, headers)

    # ══════════════════════════════════════════════════════════════
    # MODE 3: Single reading (backward compatible)
    # ══════════════════════════════════════════════════════════════
    if "temperature" not in data or "humidity" not in data:
        return ({"error": "Required: temperature, humidity."}, 400, headers)

    result = _process_single_reading(data, warehouse_id, zone_id, commodity, timestamp)
    _update_warehouse_aggregate(warehouse_id, [result])

    # BigQuery single insert
    try:
        bq.insert_rows_json(BQ_TABLE, [{
            "warehouse_id":     warehouse_id,
            "zone_id":          zone_id,
            "temperature":      data["temperature"],
            "humidity":         data["humidity"],
            "co2":              data.get("co2", 400),
            "gas_level":        data.get("gas_level", 0),
            "risk_score":       result["risk_score"],
            "risk_level":       result["risk_level"],
            "commodity_type":   commodity,
            "days_to_spoilage": result["days_to_spoilage"],
            "timestamp":        timestamp.isoformat(),
        }])
    except Exception as e:
        print(f"[BigQuery error] {e}")

    return (
        {
            "status":             "ok",
            "zone_id":            zone_id,
            "risk_level":         result["risk_level"],
            "risk_score":         result["risk_score"],
            "days_to_spoilage":   result["days_to_spoilage"],
            "recommendation":    result["recommendation"],
            "estimated_loss_inr": result["estimated_loss_inr"],
            "is_anomalous":       result["is_anomalous"],
            "anomaly_score":      result["anomaly_score"],
            "anomaly_flags":      result["anomaly_flags"],
            "timestamp":          timestamp.isoformat(),
        },
        200,
        headers,
    )