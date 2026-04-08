"""Shared fixtures for integration tests against Firebase Emulator Suite.

Requires: firebase emulators:start (Firestore on localhost:8080)
Run with: python -m pytest -m integration -v
"""

import os
import sys
import datetime
import importlib.util

import pytest

# ── Make api-function/ importable as `main` ──────────────────────────
_API_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "api-function"))
if _API_DIR not in sys.path:
    sys.path.insert(0, _API_DIR)


# ── Point Firestore to the local emulator BEFORE any client import ───
os.environ["FIRESTORE_EMULATOR_HOST"] = "localhost:8080"
os.environ["GCLOUD_PROJECT"] = "postharvest-hack"


from google.cloud import firestore  # noqa: E402  — must be imported after env var


# ═══════════════════════════════════════════════════════════════════════
# SESSION-SCOPE FIXTURES
# ═══════════════════════════════════════════════════════════════════════

@pytest.fixture(scope="session")
def firestore_client():
    """Provide a Firestore client connected to the Firestore emulator."""
    client = firestore.Client(project="postharvest-hack")
    yield client


@pytest.fixture(scope="session")
def alert_module():
    """Dynamically import alert-function/main.py as 'alert_main'.

    This avoids a naming collision with api-function/main.py (both are
    called 'main').  Uses importlib to give it a distinct module name and
    registers it in sys.modules so @patch("alert_main.xxx") works.
    """
    alert_path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "alert-function", "main.py")
    )
    spec = importlib.util.spec_from_file_location("alert_main", alert_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["alert_main"] = module          # register BEFORE exec so @patch resolves it
    spec.loader.exec_module(module)
    return module


# ═══════════════════════════════════════════════════════════════════════
# DATA SEED / CLEANUP HELPERS
# ═══════════════════════════════════════════════════════════════════════

def _delete_collection(col_ref):
    """Delete all documents in a Firestore collection reference."""
    for doc in col_ref.stream():
        doc.reference.delete()


def _cleanup_warehouse(client, wh_id):
    """Remove a warehouse and all its subcollections from the emulator."""
    wh_ref = client.collection("warehouses").document(wh_id)
    for sub in ("latest", "readings", "predictions", "alerts"):
        _delete_collection(wh_ref.collection(sub))

    # Clean up zone subcollections
    for zone_doc in wh_ref.collection("zones").stream():
        zone_ref = zone_doc.reference
        for zone_sub in ("latest", "readings"):
            _delete_collection(zone_ref.collection(zone_sub))
        zone_ref.delete()

    wh_ref.delete()


# ═══════════════════════════════════════════════════════════════════════
# PER-TEST FIXTURES
# ═══════════════════════════════════════════════════════════════════════

@pytest.fixture
def clean_firestore(firestore_client):
    """Yield the client, then wipe ALL warehouses after the test."""
    yield firestore_client
    for doc in firestore_client.collection("warehouses").stream():
        _cleanup_warehouse(firestore_client, doc.id)


@pytest.fixture
def seed_warehouse(firestore_client):
    """Seed a warehouse with latest + historical readings.  Returns the warehouse ID."""
    wh_id = "wh001"
    wh_ref = firestore_client.collection("warehouses").document(wh_id)
    wh_ref.set({
        "name": "Test Cold Storage",
        "location": "Ludhiana, Punjab",
        "commodityType": "tomato",
        "capacity": 500,
        "ownerId": "test-user-001",
        "zoneCount": 10,
        "zones": ["zone-A", "zone-B", "zone-C", "zone-D", "zone-E",
                  "zone-F", "zone-G", "zone-H", "zone-I", "zone-J"],
    })

    # Latest reading (simulating M1's predict-spoilage output)
    wh_ref.collection("latest").document("current").set({
        "temperature": 28.5,
        "humidity": 72.0,
        "co2": 450.0,
        "gasLevel": 0.2,
        "riskScore": 0.45,
        "riskLevel": "warning",
        "daysToSpoilage": 5.5,
        "estimatedLossInr": 12000.0,
        "commodityType": "tomato",
        "timestamp": datetime.datetime.utcnow(),
    })

    # Historical readings (last 3 hours)
    now = datetime.datetime.utcnow()
    for i in range(3):
        wh_ref.collection("readings").add({
            "temperature": 26.0 + i,
            "humidity": 70.0 + i,
            "co2": 400.0 + i * 20,
            "gasLevel": 0.1 + i * 0.05,
            "riskScore": 0.3 + i * 0.1,
            "riskLevel": "warning",
            "daysToSpoilage": 7.0 - i,
            "commodityType": "tomato",
            "timestamp": now - datetime.timedelta(hours=3 - i),
        })

    # Seed zone subcollections
    for zone_id in ("zone-A", "zone-B", "zone-C", "zone-D", "zone-E",
                     "zone-F", "zone-G", "zone-H", "zone-I", "zone-J"):
        zone_ref = wh_ref.collection("zones").document(zone_id)
        zone_ref.set({
            "label": zone_id.replace("-", " ").title(),
            "sensorId": "",
            "commodityType": "tomato",
            "createdAt": now,
        })
        zone_ref.collection("latest").document("current").set({
            "temperature": 28.5,
            "humidity": 72.0,
            "co2": 450.0,
            "gasLevel": 0.2,
            "riskScore": 0.45,
            "riskLevel": "warning",
            "daysToSpoilage": 5.5,
            "estimatedLossInr": 12000.0,
            "commodityType": "tomato",
            "zoneId": zone_id,
            "timestamp": now,
        })

    yield wh_id

    _cleanup_warehouse(firestore_client, wh_id)


@pytest.fixture
def seed_alert(firestore_client, seed_warehouse):
    """Seed a critical alert and return (warehouse_id, alert_id)."""
    wh_id = seed_warehouse
    wh_ref = firestore_client.collection("warehouses").document(wh_id)

    alert_ref = wh_ref.collection("alerts").document()
    alert_ref.set({
        "type": "spoilage_risk",
        "severity": "critical",
        "riskLevel": "critical",
        "riskScore": 0.85,
        "message": "Temperature 36.8\u00b0C \u2014 tomato spoilage imminent",
        "commodityType": "tomato",
        "temperature": 36.8,
        "humidity": 85.0,
        "co2": 600.0,
        "gasLevel": 0.4,
        "daysToSpoilage": 1.5,
        "estimatedLossInr": 25000.0,
        "acknowledged": False,
        "timestamp": datetime.datetime.utcnow(),
    })

    yield wh_id, alert_ref.id
    # Cleanup delegated to seed_warehouse fixture
