from google.cloud import firestore
from datetime import datetime

db = firestore.Client(project="postharvest-hack")

# ── Default zone layout per warehouse ────────────────────────────────
# Each warehouse gets a set of zones. The zone_id is used as the
# Firestore document ID under warehouses/{whId}/zones/{zoneId}.
DEFAULT_ZONES = [
    {"id": "zone-A", "label": "Zone A"},
    {"id": "zone-B", "label": "Zone B"},
    {"id": "zone-C", "label": "Zone C"},
    {"id": "zone-D", "label": "Zone D"},
    {"id": "zone-E", "label": "Zone E"},
    {"id": "zone-F", "label": "Zone F"},
    {"id": "zone-G", "label": "Zone G"},
    {"id": "zone-H", "label": "Zone H"},
    {"id": "zone-I", "label": "Zone I"},
    {"id": "zone-J", "label": "Zone J"},
]

WAREHOUSES = [
    {
        "id": "wh001",
        "name": "Demo Warehouse — Tomato Cold Store",
        "location": firestore.GeoPoint(28.6139, 77.2090),  # Delhi
        "commodityType": "tomato",
        "zones": DEFAULT_ZONES,
    },
    {
        "id": "wh002",
        "name": "Demo Warehouse — Potato Store",
        "location": firestore.GeoPoint(26.8467, 80.9462),  # Lucknow
        "commodityType": "potato",
        "zones": DEFAULT_ZONES,
    },
]

_PLACEHOLDER_LATEST = {
    "temperature": 0.0,
    "humidity": 0.0,
    "co2": 400.0,
    "gasLevel": 0.0,
    "riskScore": 0.0,
    "riskLevel": "low",
    "daysToSpoilage": 14.0,
    "recommendation": "",
    "estimatedLossInr": 0.0,
    "timestamp": datetime.utcnow(),
    "imageUrl": "",
}

for wh in WAREHOUSES:
    ref = db.collection("warehouses").document(wh["id"])
    zones = wh.get("zones", DEFAULT_ZONES)

    ref.set({
        "name": wh["name"],
        "location": wh["location"],
        "commodityType": wh["commodityType"],
        "zoneCount": len(zones),
        "zones": [z["id"] for z in zones],
        "createdAt": datetime.utcnow(),
    })

    # Seed the warehouse-level 'latest/current' (aggregate / backward-compat)
    ref.collection("latest").document("current").set(_PLACEHOLDER_LATEST)

    # Seed each zone subcollection
    for zone in zones:
        zone_ref = ref.collection("zones").document(zone["id"])
        zone_ref.set({
            "label": zone["label"],
            "sensorId": "",           # will be set when ESP32 registers
            "commodityType": wh["commodityType"],
            "createdAt": datetime.utcnow(),
        })
        # Each zone gets its own latest doc
        zone_ref.collection("latest").document("current").set({
            **_PLACEHOLDER_LATEST,
            "zoneId": zone["id"],
        })

    print(f"  {wh['id']}: {len(zones)} zones initialised")

print(f"\nFirestore initialised with {len(WAREHOUSES)} warehouses.")