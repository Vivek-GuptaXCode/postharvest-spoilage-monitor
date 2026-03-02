"""
Hardware-failure fallback simulator.

Posts synthetic sensor data to M1's predict-spoilage Cloud Function every
INTERVAL seconds.  Gradually degrades conditions to showcase real-time risk
escalation in the Flutter dashboard, SMS alerts, and Telegram notifications.

The payload schema matches what M1's Cloud Function expects:
    warehouse_id, commodity_type, temperature, humidity, co2, gas_level,
    hours_in_storage

Usage:
    python simulator.py --url https://PREDICT_SPOILAGE_URL
    python simulator.py --url https://... --commodity banana --interval 3 --posts 60
"""

import argparse
import random
import sys
import time

import requests

# ── Defaults (override via CLI args) ──────────────────────────────────
DEFAULT_URL        = "https://PREDICT_SPOILAGE_URL"
DEFAULT_WAREHOUSE  = "wh001"
DEFAULT_COMMODITY  = "tomato"
DEFAULT_INTERVAL   = 5
DEFAULT_POSTS      = 120   # 10 minutes at 5-second intervals

# Starting values (near-optimal for each commodity, from M1's commodity_thresholds.json)
COMMODITY_BASE = {
    "tomato":  {"temp": 14.0, "hum": 90.0},
    "potato":  {"temp": 4.5,  "hum": 96.0},
    "banana":  {"temp": 13.5, "hum": 92.0},
    "rice":    {"temp": 18.0, "hum": 58.0},
    "onion":   {"temp": 1.5,  "hum": 67.0},
}


def run_simulation(url: str, warehouse: str, commodity: str, interval: int, total_posts: int):
    """Run a degradation simulation posting to the Cloud Function.

    Starts at near-optimal conditions and gradually drifts temperature up
    and humidity down to simulate a cooling failure.  The Cloud Function
    should respond with escalating risk levels (low → medium → high → critical).
    """
    base = COMMODITY_BASE.get(commodity, COMMODITY_BASE["tomato"])
    base_temp = base["temp"]
    base_hum  = base["hum"]
    temp_drift = 0.12    # °C increase per post
    hum_drift  = -0.08   # % decrease per post
    hours = 24.0         # starting hours_in_storage

    print(f"{'='*60}")
    print("PostHarvest Simulator")
    print(f"URL:       {url}")
    print(f"Warehouse: {warehouse}  |  Commodity: {commodity}")
    print(f"Interval:  {interval}s  |  Posts: {total_posts}")
    print(f"{'='*60}")

    for i in range(total_posts):
        # Gradually degrade conditions with some noise
        temp = base_temp + temp_drift * i + random.gauss(0, 0.3)
        hum  = base_hum  + hum_drift  * i + random.gauss(0, 1.0)
        co2  = 420 + (temp - base_temp) * 20 + random.gauss(0, 10)
        gas  = 50  + max(0, temp - 20) * 8  + random.gauss(0, 5)

        payload = {
            "warehouse_id":     warehouse,
            "commodity_type":   commodity,
            "temperature":      round(temp, 2),
            "humidity":         round(max(hum, 20), 2),
            "co2":              round(max(co2, 300), 1),
            "gas_level":        round(max(gas, 0), 1),
            "hours_in_storage": round(hours, 2),
        }

        try:
            r = requests.post(url, json=payload, timeout=10)
            d = r.json()
            risk  = d.get("risk_level", "?")
            score = d.get("risk_score", "?")
            days  = d.get("days_to_spoilage", "?")
            print(
                f"[{i+1:>3}/{total_posts}] "
                f"Temp {payload['temperature']:>5.1f}°C  "
                f"Hum {payload['humidity']:>5.1f}%  "
                f"→ Risk: {risk:<8} Score: {score:<6}  "
                f"Shelf: {days} days  [{r.status_code}]"
            )
        except Exception as e:
            print(f"[{i+1:>3}/{total_posts}] ERROR: {e}")

        hours += interval / 3600
        time.sleep(interval)

    print(f"\n{'='*60}")
    print("Simulation complete.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="PostHarvest sensor simulator")
    parser.add_argument("--url",       default=DEFAULT_URL,
                        help="Cloud Function URL for predict-spoilage (from M1)")
    parser.add_argument("--warehouse", default=DEFAULT_WAREHOUSE,
                        help="Warehouse ID (default: wh001)")
    parser.add_argument("--commodity", default=DEFAULT_COMMODITY,
                        choices=list(COMMODITY_BASE.keys()),
                        help="Commodity type (default: tomato)")
    parser.add_argument("--interval",  type=int, default=DEFAULT_INTERVAL,
                        help="Seconds between posts (default: 5)")
    parser.add_argument("--posts",     type=int, default=DEFAULT_POSTS,
                        help="Total number of posts (default: 120)")
    args = parser.parse_args()

    if "REPLACE" in args.url:
        print("ERROR: Replace the FUNCTION_URL in simulator.py or pass --url")
        print("  Get the URL from M1:")
        print("  gcloud functions describe predict-spoilage --gen2 --region=asia-south1 "
              "--format='value(serviceConfig.uri)'")
        sys.exit(1)

    run_simulation(args.url, args.warehouse, args.commodity, args.interval, args.posts)
