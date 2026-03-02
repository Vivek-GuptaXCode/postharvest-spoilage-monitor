"""
Seed 24 hours of historical sensor data into Firestore + BigQuery.

Posts data to M1's predict-spoilage Cloud Function with a mild day/night
cycle so charts look realistic during the demo.  The Cloud Function handles
writing to Firestore (latest, readings, predictions, alerts) and BigQuery.

Usage:
    python seed_historical.py --url https://PREDICT_SPOILAGE_URL
    python seed_historical.py --url https://... --commodity potato --warehouse wh002
"""

import argparse
import random
import sys
import time
from datetime import datetime, timedelta

import requests

# ── Configuration ─────────────────────────────────────────────────────
DEFAULT_URL       = "https://REPLACE_WITH_PREDICT_SPOILAGE_URL"
WAREHOUSE_ID      = "wh001"
COMMODITY         = "tomato"
DURATION_HOURS    = 24
INTERVAL_MIN      = 2           # one reading every 2 min → 720 data points
BASE_TEMP         = 13.5        # near-optimal for tomato (12–15 °C)
BASE_HUM          = 91.0        # near-optimal for tomato (85–95 %)

# Commodity base values (from M1's commodity_thresholds.json)
COMMODITY_BASES = {
    "tomato":  {"temp": 13.5, "hum": 91.0},
    "potato":  {"temp": 4.5,  "hum": 96.0},
    "banana":  {"temp": 13.5, "hum": 92.0},
    "rice":    {"temp": 18.0, "hum": 58.0},
    "onion":   {"temp": 1.5,  "hum": 67.0},
}


def seed(url: str, warehouse: str = WAREHOUSE_ID, commodity: str = COMMODITY):
    """Seed 24 hours of historical data with a realistic day/night temperature cycle."""
    base = COMMODITY_BASES.get(commodity, COMMODITY_BASES["tomato"])
    base_temp = base["temp"]
    base_hum = base["hum"]

    total = DURATION_HOURS * 60 // INTERVAL_MIN
    start_time = datetime.utcnow() - timedelta(hours=DURATION_HOURS)
    print(f"Seeding {total} data points over {DURATION_HOURS}h for {commodity} in {warehouse}...")

    success_count = 0
    error_count = 0

    for i in range(total):
        ts = start_time + timedelta(minutes=i * INTERVAL_MIN)
        hour_of_day = ts.hour

        # Day/night effect: warmer during 10:00–18:00
        day_effect = 3.0 if 10 <= hour_of_day <= 18 else 0.0

        temp = base_temp + day_effect + random.gauss(0, 0.6)
        hum  = base_hum  - day_effect * 0.8 + random.gauss(0, 1.2)
        co2  = 420 + (temp - base_temp) * 15 + random.gauss(0, 8)
        gas  = 50  + max(0, temp - 16) * 4 + random.gauss(0, 4)

        payload = {
            "warehouse_id":    warehouse,
            "commodity_type":  commodity,
            "temperature":     round(temp, 2),
            "humidity":        round(max(hum, 40), 2),
            "co2":             round(max(co2, 300), 1),
            "gas_level":       round(max(gas, 0), 1),
            "hours_in_storage": round(i * INTERVAL_MIN / 60, 2),
        }

        try:
            r = requests.post(url, json=payload, timeout=10)
            if r.status_code == 200:
                success_count += 1
            else:
                error_count += 1
            if (i + 1) % 50 == 0 or i == 0:
                print(f"  [{i+1:>4}/{total}] — {r.status_code}  "
                      f"(temp={payload['temperature']:.1f}°C, hum={payload['humidity']:.1f}%)")
        except Exception as e:
            error_count += 1
            print(f"  [{i+1:>4}/{total}] ERROR: {e}")

        # Fast seeding: 0.15s sleep → ~2 min total runtime for 720 points
        time.sleep(0.15)

    print(f"\nDone — {success_count} readings seeded successfully, {error_count} errors.")
    print(f"Verify in Firebase Console → Firestore → warehouses/{warehouse}/readings")
    print(f"Verify in BigQuery: bq query 'SELECT COUNT(*) FROM postharvest.sensor_readings'")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed historical sensor data for demo")
    parser.add_argument("--url",       default=DEFAULT_URL,
                        help="Cloud Function URL for predict-spoilage (from M1)")
    parser.add_argument("--warehouse", default=WAREHOUSE_ID,
                        help="Warehouse ID (default: wh001)")
    parser.add_argument("--commodity", default=COMMODITY,
                        choices=list(COMMODITY_BASES.keys()),
                        help="Commodity type (default: tomato)")
    args = parser.parse_args()

    if "REPLACE" in args.url:
        print("ERROR: Pass --url <FUNCTION_URL>")
        print("  Get the URL from M1:")
        print("  gcloud functions describe predict-spoilage --gen2 --region=asia-south1 "
              "--format='value(serviceConfig.uri)'")
        sys.exit(1)

    seed(args.url, args.warehouse, args.commodity)
