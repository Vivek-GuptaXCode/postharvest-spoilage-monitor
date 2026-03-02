

import random
from datetime import datetime, timedelta

from google.cloud import bigquery, firestore

# ── Configuration ─────────────────────────────────────────────────────
PROJECT_ID   = "postharvest-hack"
BQ_TABLE     = f"{PROJECT_ID}.postharvest.sensor_readings"
WAREHOUSE_ID = "wh001"
COMMODITY    = "tomato"

DURATION_HOURS = 24
INTERVAL_MIN   = 2
TOTAL = DURATION_HOURS * 60 // INTERVAL_MIN  # 720 points

db = firestore.Client(project=PROJECT_ID)
bq = bigquery.Client(project=PROJECT_ID)

start_time = datetime.utcnow() - timedelta(hours=DURATION_HOURS)
BASE_TEMP = 13.5
BASE_HUM  = 91.0

print(f"Seeding {TOTAL} historical data points over {DURATION_HOURS}h …")

bq_rows = []
wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)

for i in range(TOTAL):
    ts = start_time + timedelta(minutes=i * INTERVAL_MIN)
    hour_of_day = ts.hour

    # Day/night cycle + gradual degradation in 2nd half
    day_effect = 3.0 * (1 if 10 <= hour_of_day <= 18 else 0)
    # After hour 12, simulate cooling failure (temp drifts up)
    t_frac = i / TOTAL
    drift = max(0, (t_frac - 0.5) * 20)  # 0 for first 12h, up to +10°C by hour 24

    temp = BASE_TEMP + day_effect + drift + random.gauss(0, 0.6)
    hum  = BASE_HUM - day_effect * 0.8 - drift * 0.5 + random.gauss(0, 1.2)
    co2  = 420 + (temp - 13.5) * 15 + random.gauss(0, 8)
    gas  = 50 + max(0, temp - 16) * 4 + random.gauss(0, 4)
    hours = i * INTERVAL_MIN / 60

    temp = round(temp, 2)
    hum  = round(max(min(hum, 100), 40), 2)
    co2  = round(max(co2, 300), 1)
    gas  = round(max(gas, 0), 1)

    # ── Simple risk estimate (mirrors Cloud Function logic) ───────
    temp_dev = abs(temp - 13.5)
    stress = temp_dev * hours
    risk_score = round(min(100, max(0, stress / 20)), 2)
    if risk_score <= 25:    risk_level = "low"
    elif risk_score <= 50:  risk_level = "medium"
    elif risk_score <= 75:  risk_level = "high"
    else:                   risk_level = "critical"
    days_to_spoilage = round(max(0, 14 * (1 - risk_score / 100)), 2)

    # ── Firestore: readings subcollection (backdated timestamp) ───
    wh_ref.collection("readings").add({
        "temperature":    temp,
        "humidity":       hum,
        "co2":            co2,
        "gasLevel":       gas,
        "riskScore":      risk_score,
        "riskLevel":      risk_level,
        "daysToSpoilage": days_to_spoilage,
        "recommendation": "",
        "estimatedLossInr": 0.0,
        "timestamp":      ts,
        "imageUrl":       "",
    })

    # ── BigQuery row (batch insert later) ─────────────────────────
    bq_rows.append({
        "warehouse_id":     WAREHOUSE_ID,
        "temperature":      temp,
        "humidity":         hum,
        "co2":              co2,
        "gas_level":        gas,
        "risk_score":       risk_score,
        "risk_level":       risk_level,
        "commodity_type":   COMMODITY,
        "days_to_spoilage": days_to_spoilage,
        "timestamp":        ts.isoformat(),
    })

    if (i + 1) % 100 == 0:
        errors = bq.insert_rows_json(BQ_TABLE, bq_rows)
        if errors:
            print(f"  BigQuery errors: {errors}")
        bq_rows = []
        print(f"  [{i+1}/{TOTAL}] seeded")

# Flush remaining rows
if bq_rows:
    errors = bq.insert_rows_json(BQ_TABLE, bq_rows)
    if errors:
        print(f"  BigQuery errors: {errors}")

print(f"\nDone. {TOTAL} readings seeded with timestamps from "
      f"{start_time.strftime('%H:%M')} to {datetime.utcnow().strftime('%H:%M')} UTC.")
