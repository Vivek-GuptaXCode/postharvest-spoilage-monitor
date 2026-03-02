from google.cloud import firestore
from datetime import datetime

db = firestore.Client(project="postharvest-hack")

WAREHOUSES = [
    {
        "id": "wh001",
        "name": "Demo Warehouse — Tomato Cold Store",
        "location": firestore.GeoPoint(28.6139, 77.2090),  # Delhi
        "commodityType": "tomato",
    },
    {
        "id": "wh002",
        "name": "Demo Warehouse — Potato Store",
        "location": firestore.GeoPoint(26.8467, 80.9462),  # Lucknow
        "commodityType": "potato",
    },
]

for wh in WAREHOUSES:
    ref = db.collection("warehouses").document(wh["id"])
    ref.set({
        "name": wh["name"],
        "location": wh["location"],
        "commodityType": wh["commodityType"],
        "createdAt": datetime.utcnow(),
    })

    # Seed the 'latest/current' subdocument with placeholder values
    ref.collection("latest").document("current").set({
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
    })

print("Firestore initialised with", len(WAREHOUSES), "warehouses.")