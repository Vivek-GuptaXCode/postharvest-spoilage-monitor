import os
import sys
import time
import pytest
import subprocess
import requests

# Add function source dirs to path so we can import them
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'api-function'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'alert-function'))

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
FIRESTORE_EMULATOR_HOST = "localhost:8080"
FUNCTIONS_EMULATOR_HOST = "localhost:5001"
EMULATOR_UI_HOST = "localhost:4000"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session", autouse=True)
def set_emulator_env():
    """Point all Google Cloud / Firebase SDKs at the local emulators."""
    os.environ["FIRESTORE_EMULATOR_HOST"] = FIRESTORE_EMULATOR_HOST
    os.environ["GCLOUD_PROJECT"] = "postharvest-hack"
    os.environ["GCP_PROJECT"] = "postharvest-hack"
    # Disable real Twilio / Telegram during tests
    os.environ["TWILIO_ACCOUNT_SID"] = "ACtest_fake_sid_for_local_testing"
    os.environ["TWILIO_AUTH_TOKEN"] = "fake_auth_token_for_local_testing"
    os.environ["TWILIO_FROM_NUMBER"] = "+15005550006"
    os.environ["TELEGRAM_BOT_TOKEN"] = "0000000000:FAKE_TOKEN_FOR_TESTING"
    os.environ["TELEGRAM_CHAT_ID"] = "000000000"
    os.environ["ALERT_PHONE_NUMBERS"] = "+919999999999"
    yield


@pytest.fixture(scope="session")
def firestore_client(set_emulator_env):
    """Return a Firestore client pointing at the emulator."""
    from google.cloud import firestore
    client = firestore.Client(project="postharvest-hack")
    return client


@pytest.fixture(autouse=True)
def clean_firestore(firestore_client):
    """Wipe emulator Firestore data before each test."""
    # The emulator exposes a REST endpoint to clear all data
    try:
        requests.delete(
            f"http://{FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/postharvest-hack/databases/(default)/documents"
        )
    except requests.ConnectionError:
        pytest.skip("Firestore emulator not running — start it with: firebase emulators:start")
    yield


@pytest.fixture
def seed_warehouse(firestore_client):
    """Seed a test warehouse document and return its ID."""
    wh_id = "test-warehouse-001"
    wh_ref = firestore_client.collection("warehouses").document(wh_id)
    wh_ref.set({
        "name": "Test Warehouse Alpha",
        "location": "Chandigarh",
        "commodityType": "wheat",
        "capacity": 500,
        "ownerId": "test-user-001",
        "createdAt": firestore_client.field_path("SERVER_TIMESTAMP"),
    })

    # Seed a "latest/current" doc (matches M1's schema)
    wh_ref.collection("latest").document("current").set({
        "temperature": 32.5,
        "humidity": 68.0,
        "co2": 420.0,
        "gasLevel": 0.15,
        "riskScore": 0.72,
        "riskLevel": "warning",
        "daysToSpoilage": 4.2,
        "estimatedLossInr": 12500.0,
        "commodityType": "wheat",
        "timestamp": firestore_client._NOW if hasattr(firestore_client, '_NOW') else __import__('datetime').datetime.utcnow(),
    })

    # Seed a reading in the readings subcollection
    import datetime
    wh_ref.collection("readings").add({
        "temperature": 32.5,
        "humidity": 68.0,
        "co2": 420.0,
        "gasLevel": 0.15,
        "riskScore": 0.72,
        "riskLevel": "warning",
        "daysToSpoilage": 4.2,
        "estimatedLossInr": 12500.0,
        "commodityType": "wheat",
        "timestamp": datetime.datetime.utcnow(),
    })

    return wh_id


@pytest.fixture
def seed_alert(firestore_client, seed_warehouse):
    """Seed an alert document and return (warehouse_id, alert_id)."""
    import datetime
    wh_id = seed_warehouse
    alert_ref = firestore_client.collection("warehouses").document(wh_id).collection("alerts").document()
    alert_ref.set({
        "riskLevel": "critical",
        "riskScore": 0.92,
        "message": "Temperature exceeded 35°C — spoilage imminent",
        "commodityType": "wheat",
        "temperature": 37.2,
        "humidity": 82.0,
        "co2": 680.0,
        "gasLevel": 0.45,
        "daysToSpoilage": 1.1,
        "estimatedLossInr": 45000.0,
        "acknowledged": False,
        "timestamp": datetime.datetime.utcnow(),
    })
    return wh_id, alert_ref.id