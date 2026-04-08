"""
PostHarvest — Firebase Real-Time Receiver
Listens to Firestore for zone-level data updates and displays them.

READ-ONLY: This code never writes to Firestore.

Data flow:
  ESP32 → AES-128 encrypt → Gateway → Cloud Function → decrypt → ML → Firestore (plaintext)
                                                                          ↓
                                                              This receiver reads & displays
"""

import firebase_admin
from firebase_admin import credentials, firestore
import os
import time
from datetime import datetime

# ══════════════════════════════════════════════════════════════
#  CONFIG
# ══════════════════════════════════════════════════════════════

WAREHOUSE_ID = "wh001"

ZONES = [
    "zone-A", "zone-B", "zone-C", "zone-D", "zone-E",
    "zone-F", "zone-G", "zone-H", "zone-I", "zone-J",
]

# Firebase service account key (relative to this file)
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
#  PRINT FUNCTIONS
# ══════════════════════════════════════════════════════════════

def print_zone_data(zone_id, data):
    """Print single zone row from Firestore document fields."""
    risk = data.get("riskLevel", "?")
    risk_icon = {"low": "🟢", "medium": "🟡", "high": "🟠", "critical": "🔴"}.get(risk, "⚪")
    print(
        f"  {risk_icon} {zone_id:<10} "
        f"{data.get('commodityType', '?'):<10} "
        f"{data.get('temperature', 0):>7.1f}°C "
        f"{data.get('humidity', 0):>6.1f}% "
        f"{data.get('co2', 0):>6.0f} "
        f"{data.get('gasLevel', 0):>6.1f} "
        f"{data.get('riskScore', 0):>6.1f} "
        f"{data.get('daysToSpoilage', 0):>6.1f}d "
        f"[{risk}]"
    )


def print_full_table(all_zone_data):
    """Print complete warehouse table."""
    print(f"\n{'=' * 95}")
    print(f"  RECEIVER │ WAREHOUSE: {WAREHOUSE_ID} │ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'=' * 95}")
    print(
        f"     {'ZONE':<10} {'COMMODITY':<10} "
        f"{'TEMP':>8} {'RH%':>7} {'CO2':>7} {'GAS':>7} "
        f"{'RISK':>7} {'SPOIL':>7} LEVEL"
    )
    print(f"  {'-' * 90}")

    for zone_id in sorted(all_zone_data.keys()):
        data = all_zone_data[zone_id]
        if data:
            print_zone_data(zone_id, data)
        else:
            print(f"  ⚪ {zone_id:<10} -- no data --")

    print(f"  {'-' * 90}")
    print(f"  Source: Firestore (Cloud Function writes plaintext after AES-128 decrypt + ML)")
    print(f"{'=' * 95}\n")


def print_alert(alert_data):
    """Print alert from Firestore."""
    severity = alert_data.get("severity", "?")
    icon = "🔴" if severity == "critical" else "🟠"
    print(f"\n  {icon} *** ALERT ***")
    print(f"  Zone      : {alert_data.get('zoneId', '?')}")
    print(f"  Type      : {alert_data.get('type', '?')}")
    print(f"  Severity  : {severity}")
    print(f"  Message   : {alert_data.get('message', '?')}")
    print(f"  ***********\n")


# ══════════════════════════════════════════════════════════════
#  REAL-TIME LISTENERS (READ-ONLY)
# ══════════════════════════════════════════════════════════════

# Store latest data for all zones
latest_data = {}


def on_zone_snapshot(doc_snapshot, changes, read_time):
    """Called when any zone's latest/current document changes."""
    for doc in doc_snapshot:
        if not doc.exists:
            continue
        data = doc.to_dict()
        zone_id = data.get("zoneId", "unknown")
        latest_data[zone_id] = data

        # Print table when all zones have data
        if len(latest_data) >= len(ZONES):
            print_full_table(latest_data)


def on_warehouse_snapshot(doc_snapshot, changes, read_time):
    """Called when warehouse-level latest/current changes."""
    for doc in doc_snapshot:
        if not doc.exists:
            continue
        data = doc.to_dict()
        risk = data.get("riskLevel", "?")
        score = data.get("riskScore", 0)
        zones = data.get("zoneCount", "?")
        print(
            f"  📊 Warehouse aggregate updated: "
            f"risk={risk} score={score:.1f} zones={zones}"
        )


def on_alert_snapshot(doc_snapshot, changes, read_time):
    """Called when a new alert is added."""
    for change in changes:
        if change.type.name == "ADDED":
            alert_data = change.document.to_dict()
            print_alert(alert_data)


# ══════════════════════════════════════════════════════════════
#  START LISTENERS
# ══════════════════════════════════════════════════════════════

def start_listeners():
    """Start real-time Firestore listeners for all zones (read-only)."""

    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)

    # Listen to each zone's latest/current
    zone_watchers = []
    for zone_id in ZONES:
        doc_ref = (
            wh_ref.collection("zones")
            .document(zone_id)
            .collection("latest")
            .document("current")
        )
        watcher = doc_ref.on_snapshot(on_zone_snapshot)
        zone_watchers.append(watcher)
        print(f"  👂 Listening: {zone_id}")

    # Listen to warehouse-level latest
    wh_latest_ref = wh_ref.collection("latest").document("current")
    wh_watcher = wh_latest_ref.on_snapshot(on_warehouse_snapshot)

    # Listen to alerts (last 5)
    alerts_ref = wh_ref.collection("alerts").order_by("timestamp").limit_to_last(5)
    alert_watcher = alerts_ref.on_snapshot(on_alert_snapshot)

    print(f"\n  All listeners active. Waiting for data...\n")

    return zone_watchers, wh_watcher, alert_watcher


# ══════════════════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print(f"\n{'=' * 60}")
    print(f"  PostHarvest — Firebase Receiver (Real-Time)")
    print(f"  Reads data from Firestore and displays it")
    print(f"{'=' * 60}")
    print(f"  Warehouse  : {WAREHOUSE_ID}")
    print(f"  Zones      : {len(ZONES)}")
    print(f"  Mode       : Real-time listener (READ-ONLY)")
    print(f"  Security   : Data encrypted in-transit (AES-128-CBC)")
    print(f"               Decrypted by Cloud Function before storage")
    print(f"{'=' * 60}\n")

    watchers = start_listeners()

    # Keep running
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n  Receiver stopped.")
