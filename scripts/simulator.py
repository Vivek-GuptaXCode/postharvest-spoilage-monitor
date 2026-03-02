import json
import random
import time
from datetime import datetime

import requests

# ── Configuration ─────────────────────────────────────────────────────
FUNCTION_URL = "https://predict-spoilage-n6hvbwpdfq-el.a.run.app"
WAREHOUSE_ID = "wh001"
COMMODITY    = "tomato"
INTERVAL_SEC = 5          # posting frequency during demo
TOTAL_POSTS  = 120        # 10 minutes of data at 5-second intervals


BASE_TEMP = 14.0           # optimal for tomato
BASE_HUM  = 90.0
TEMP_DRIFT_PER_POST = 0.12
HUM_DRIFT_PER_POST  = -0.08
BASE_CO2  = 420
BASE_GAS  = 50

SIMULATED_HOURS_PER_POST = 168.0 / TOTAL_POSTS  # ~1.4 h per post
hours_in_storage = 0.0     # start from arrival at warehouse

print(f"Simulator: posting to {FUNCTION_URL}")
print(f"Commodity: {COMMODITY}  |  Interval: {INTERVAL_SEC}s  |  Posts: {TOTAL_POSTS}")
print("-" * 60)

for i in range(TOTAL_POSTS):
    temp = BASE_TEMP + TEMP_DRIFT_PER_POST * i + random.gauss(0, 0.3)
    hum  = BASE_HUM  + HUM_DRIFT_PER_POST  * i + random.gauss(0, 1.0)
    co2  = BASE_CO2  + (temp - BASE_TEMP) * 20  + random.gauss(0, 10)
    gas  = BASE_GAS  + max(0, temp - 20) * 8    + random.gauss(0, 5)

    payload = {
        "warehouse_id":    WAREHOUSE_ID,
        "commodity_type":  COMMODITY,
        "temperature":     round(temp, 2),
        "humidity":        round(max(hum, 30), 2),
        "co2":             round(max(co2, 300), 1),
        "gas_level":       round(max(gas, 0), 1),
        "hours_in_storage": round(hours_in_storage, 2),
    }

    try:
        r = requests.post(
            FUNCTION_URL,
            json=payload,
            headers={"Content-Type": "application/json"},
            timeout=10,
        )
        resp = r.json()
        risk = resp.get("risk_level", "?")
        score = resp.get("risk_score", "?")
        days = resp.get("days_to_spoilage", "?")
        print(
            f"[{i+1:>3}/{TOTAL_POSTS}] "
            f"Temp {payload['temperature']:>5.1f} °C  "
            f"Hum {payload['humidity']:>5.1f} %  "
            f"→ Risk: {risk:<8} Score: {score:<6}  "
            f"Shelf life: {days} days  "
            f"[{r.status_code}]"
        )
    except Exception as e:
        print(f"[{i+1:>3}/{TOTAL_POSTS}] ERROR: {e}")

    hours_in_storage += SIMULATED_HOURS_PER_POST
    time.sleep(INTERVAL_SEC)

print("\nSimulation complete.")