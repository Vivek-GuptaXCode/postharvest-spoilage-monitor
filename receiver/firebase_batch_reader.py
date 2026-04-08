"""
PostHarvest — Firebase Batch Reader (One-Time Read)
Reads data from Firestore and displays it via an interactive menu.

READ-ONLY: This code never writes to Firestore.
"""

import firebase_admin
from firebase_admin import credentials, firestore
import os
from datetime import datetime

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

RISK_ICON = {"low": "🟢", "medium": "🟡", "high": "🟠", "critical": "🔴"}


# ══════════════════════════════════════════════════════════════
#  READ WAREHOUSE INFO
# ══════════════════════════════════════════════════════════════

def read_warehouse_info():
    """Read warehouse document (read-only)."""
    doc = db.collection("warehouses").document(WAREHOUSE_ID).get()
    if doc.exists:
        info = doc.to_dict()
        print(f"\n  Warehouse : {info.get('name', WAREHOUSE_ID)}")
        print(f"  Location  : {info.get('location', '?')}")
        print(f"  Commodity : {info.get('commodityType', '?')}")
        print(f"  Zones     : {info.get('zoneCount', '?')}")
        print(f"  Created   : {info.get('createdAt', '?')}")
    else:
        print(f"  Warehouse {WAREHOUSE_ID} not found in Firestore")


# ══════════════════════════════════════════════════════════════
#  READ LATEST DATA FOR ALL ZONES
# ══════════════════════════════════════════════════════════════

def read_all_zones_latest():
    """Read latest data for each zone (read-only)."""

    print(f"\n{'=' * 100}")
    print(f"  WAREHOUSE: {WAREHOUSE_ID} │ Latest Zone Data │ {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'=' * 100}")
    print(
        f"     {'ZONE':<10} {'COMMODITY':<10} "
        f"{'TEMP':>8} {'RH%':>7} {'CO2':>7} {'GAS':>7} "
        f"{'RISK':>7} {'SPOIL':>7} {'LOSS(₹)':>9} LEVEL"
    )
    print(f"  {'-' * 95}")

    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)

    for zone_id in ZONES:
        doc_ref = (
            wh_ref.collection("zones")
            .document(zone_id)
            .collection("latest")
            .document("current")
        )
        doc = doc_ref.get()

        if not doc.exists:
            print(f"  ⚪ {zone_id:<10} -- no data --")
            continue

        d = doc.to_dict()
        risk = d.get("riskLevel", "?")
        icon = RISK_ICON.get(risk, "⚪")
        print(
            f"  {icon} {zone_id:<10} "
            f"{d.get('commodityType', '?'):<10} "
            f"{d.get('temperature', 0):>7.1f}°C "
            f"{d.get('humidity', 0):>6.1f}% "
            f"{d.get('co2', 0):>6.0f} "
            f"{d.get('gasLevel', 0):>6.1f} "
            f"{d.get('riskScore', 0):>6.1f} "
            f"{d.get('daysToSpoilage', 0):>6.1f}d "
            f"{d.get('estimatedLossInr', 0):>8.0f} "
            f"[{risk}]"
        )

    print(f"  {'-' * 95}")
    print(f"  Source: Firestore (Cloud Function → ML predict → zone-aware write)")
    print(f"{'=' * 100}\n")


# ══════════════════════════════════════════════════════════════
#  READ WAREHOUSE AGGREGATE
# ══════════════════════════════════════════════════════════════

def read_warehouse_aggregate():
    """Read warehouse-level aggregate latest (read-only)."""

    print(f"\n{'=' * 60}")
    print(f"  WAREHOUSE AGGREGATE: {WAREHOUSE_ID}")
    print(f"{'=' * 60}")

    doc = (
        db.collection("warehouses")
        .document(WAREHOUSE_ID)
        .collection("latest")
        .document("current")
        .get()
    )

    if not doc.exists:
        print(f"  No aggregate data found")
        return

    d = doc.to_dict()
    risk = d.get("riskLevel", "?")
    icon = RISK_ICON.get(risk, "⚪")
    print(f"  {icon} Risk Level       : {risk}")
    print(f"    Avg Risk Score   : {d.get('riskScore', 0):.1f}")
    print(f"    Max Risk Score   : {d.get('maxRiskScore', 0):.1f}")
    print(f"    Min Days Spoil   : {d.get('daysToSpoilage', 0):.1f}")
    print(f"    Total Loss (₹)  : {d.get('estimatedLossInr', 0):.0f}")
    print(f"    Zone Count       : {d.get('zoneCount', '?')}")
    ts = d.get("timestamp", "?")
    if hasattr(ts, "strftime"):
        ts = ts.strftime("%Y-%m-%d %H:%M:%S")
    print(f"    Last Updated     : {ts}")
    print(f"{'=' * 60}\n")


# ══════════════════════════════════════════════════════════════
#  READ ZONE HISTORY
# ══════════════════════════════════════════════════════════════

def read_zone_history(zone_id, limit=10):
    """Read history for a specific zone (read-only)."""

    print(f"\n{'=' * 90}")
    print(f"  HISTORY: {zone_id} │ Last {limit} readings")
    print(f"{'=' * 90}")

    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    readings_ref = (
        wh_ref.collection("zones")
        .document(zone_id)
        .collection("readings")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit)
    )

    docs = list(readings_ref.stream())

    print(
        f"  {'#':<4} {'TIMESTAMP':<22} {'TEMP':>7} {'RH%':>7} "
        f"{'CO2':>6} {'GAS':>6} {'RISK':>6} {'SPOIL':>7} LEVEL"
    )
    print(f"  {'-' * 80}")

    if not docs:
        print(f"  No history found for {zone_id}")
    else:
        for i, doc in enumerate(docs, 1):
            d = doc.to_dict()
            ts = d.get("timestamp", "?")
            if hasattr(ts, "strftime"):
                ts = ts.strftime("%Y-%m-%d %H:%M:%S")
            risk = d.get("riskLevel", "?")
            icon = RISK_ICON.get(risk, "⚪")
            print(
                f"  {i:<4} {str(ts):<22} "
                f"{d.get('temperature', 0):>6.1f}°C "
                f"{d.get('humidity', 0):>6.1f}% "
                f"{d.get('co2', 0):>5.0f} "
                f"{d.get('gasLevel', 0):>5.1f} "
                f"{d.get('riskScore', 0):>5.1f} "
                f"{d.get('daysToSpoilage', 0):>6.1f}d "
                f"{icon} {risk}"
            )

    print(f"  {'-' * 80}")
    print(f"{'=' * 90}\n")


# ══════════════════════════════════════════════════════════════
#  READ ALERTS
# ══════════════════════════════════════════════════════════════

def read_alerts(limit=20):
    """Read recent alerts (read-only)."""

    print(f"\n{'=' * 95}")
    print(f"  ALERTS │ Last {limit}")
    print(f"{'=' * 95}")

    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    alerts_ref = (
        wh_ref.collection("alerts")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit)
    )

    docs = list(alerts_ref.stream())

    print(
        f"  {'#':<4} {'ZONE':<10} {'SEVERITY':<10} {'TYPE':<15} "
        f"{'ACK':>4} {'TIMESTAMP':<22}"
    )
    print(f"  {'-' * 70}")

    if not docs:
        print(f"  No alerts found")
    else:
        for i, doc in enumerate(docs, 1):
            d = doc.to_dict()
            ts = d.get("timestamp", "?")
            if hasattr(ts, "strftime"):
                ts = ts.strftime("%Y-%m-%d %H:%M:%S")
            severity = d.get("severity", "?")
            icon = "🔴" if severity == "critical" else "🟠"
            ack = "✓" if d.get("acknowledged", False) else "✗"
            print(
                f"  {i:<4} {icon} {d.get('zoneId', '?'):<8} "
                f"{severity:<10} {d.get('type', '?'):<15} "
                f"{ack:>4} {str(ts):<22}"
            )
            msg = d.get("message", "")
            if msg:
                # Truncate long messages
                if len(msg) > 80:
                    msg = msg[:77] + "..."
                print(f"       └─ {msg}")

    print(f"  {'-' * 70}")
    print(f"{'=' * 95}\n")


# ══════════════════════════════════════════════════════════════
#  READ WAREHOUSE-LEVEL READINGS
# ══════════════════════════════════════════════════════════════

def read_warehouse_readings(limit=10):
    """Read warehouse-level readings (read-only)."""

    print(f"\n{'=' * 95}")
    print(f"  WAREHOUSE READINGS │ Last {limit}")
    print(f"{'=' * 95}")

    wh_ref = db.collection("warehouses").document(WAREHOUSE_ID)
    readings_ref = (
        wh_ref.collection("readings")
        .order_by("timestamp", direction=firestore.Query.DESCENDING)
        .limit(limit)
    )

    docs = list(readings_ref.stream())

    print(
        f"  {'#':<4} {'ZONE':<10} {'COMMODITY':<10} "
        f"{'TEMP':>7} {'RH%':>7} {'RISK':>6} {'SPOIL':>7} {'TIMESTAMP':<22}"
    )
    print(f"  {'-' * 85}")

    if not docs:
        print(f"  No readings found")
    else:
        for i, doc in enumerate(docs, 1):
            d = doc.to_dict()
            ts = d.get("timestamp", "?")
            if hasattr(ts, "strftime"):
                ts = ts.strftime("%Y-%m-%d %H:%M:%S")
            risk = d.get("riskLevel", "?")
            icon = RISK_ICON.get(risk, "⚪")
            print(
                f"  {i:<4} {icon} {d.get('zoneId', '?'):<8} "
                f"{d.get('commodityType', '?'):<10} "
                f"{d.get('temperature', 0):>6.1f}°C "
                f"{d.get('humidity', 0):>6.1f}% "
                f"{d.get('riskScore', 0):>5.1f} "
                f"{d.get('daysToSpoilage', 0):>6.1f}d "
                f"{str(ts):<22}"
            )

    print(f"  {'-' * 85}")
    print(f"{'=' * 95}\n")


# ══════════════════════════════════════════════════════════════
#  MAIN — INTERACTIVE MENU
# ══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print(f"\n{'=' * 60}")
    print(f"  PostHarvest — Firebase Batch Reader")
    print(f"  Reads data from Firestore (READ-ONLY)")
    print(f"{'=' * 60}")
    print(f"  Warehouse  : {WAREHOUSE_ID}")
    print(f"  Data       : Plaintext (decrypted by Cloud Function)")
    print(f"{'=' * 60}\n")

    while True:
        print("  Menu:")
        print("  1. Warehouse Info")
        print("  2. Warehouse Aggregate (latest)")
        print("  3. All Zones (Latest)")
        print("  4. Zone History")
        print("  5. Alerts")
        print("  6. Warehouse Readings")
        print("  7. Full Report (All of above)")
        print("  0. Exit")

        choice = input("\n  Enter choice: ").strip()

        if choice == "1":
            read_warehouse_info()
        elif choice == "2":
            read_warehouse_aggregate()
        elif choice == "3":
            read_all_zones_latest()
        elif choice == "4":
            zone = input("  Enter zone (e.g. zone-A): ").strip()
            count = input("  How many readings? (default 10): ").strip()
            count = int(count) if count else 10
            read_zone_history(zone, count)
        elif choice == "5":
            read_alerts()
        elif choice == "6":
            read_warehouse_readings()
        elif choice == "7":
            read_warehouse_info()
            read_warehouse_aggregate()
            read_all_zones_latest()
            read_alerts()
            read_warehouse_readings()
            for z in ZONES[:3]:  # First 3 zones to avoid too much output
                read_zone_history(z, 3)
        elif choice == "0":
            print("  Exiting.")
            break
        else:
            print("  Invalid choice.")
