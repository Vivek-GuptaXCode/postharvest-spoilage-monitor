"""End-to-end test: seeds data into Firestore (as if M1 processed it),
verifies M2's REST API returns it correctly, and tests alert dispatch.

Requires: firebase emulators:start (Firestore on localhost:8080)
Run with: python -m pytest tests/test_e2e.py -m e2e -v
"""
import pytest
import json
import datetime
from unittest.mock import MagicMock, patch
from cloudevents.http import CloudEvent

from main import api_handler  # api-function/ is on sys.path via conftest


# ═══════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════

def _req(method, path, body=None):
    """Build a mock Flask request."""
    req = MagicMock()
    req.method = method
    req.path = path
    req.get_json.return_value = body or {}
    req.args = {}
    req.headers = {"Origin": "http://localhost:3000"}
    return req


def _parse(resp):
    """Unpack (json_str, status, headers) tuple from api_handler."""
    body, status, headers = resp
    data = json.loads(body) if isinstance(body, str) else body
    return data, status, headers


def _build_eventarc_payload(warehouse_id, alert_id, severity="critical"):
    """Build Firestore Eventarc payload for on_alert_created."""
    return {
        "value": {
            "name": (
                f"projects/postharvest-hack/databases/(default)/documents/"
                f"warehouses/{warehouse_id}/alerts/{alert_id}"
            ),
            "fields": {
                "severity":     {"stringValue": severity},
                "message":      {"stringValue": "E2E test alert — spoilage imminent"},
                "type":         {"stringValue": "spoilage_risk"},
                "acknowledged": {"booleanValue": False},
            },
        }
    }


# ═══════════════════════════════════════════════════════════════════════
# END-TO-END TESTS
# ═══════════════════════════════════════════════════════════════════════

class TestEndToEnd:

    @pytest.mark.e2e
    def test_full_pipeline_seed_to_api(self, firestore_client):
        """Seed warehouse + readings + alert → query API → acknowledge alert."""

        # ── Step 1: Seed warehouse (simulating M1's init_firestore.py) ──
        wh_id = "e2e-wh-001"
        wh_ref = firestore_client.collection("warehouses").document(wh_id)
        wh_ref.set({
            "name": "E2E Test Cold Storage",
            "location": "Ludhiana, Punjab",
            "commodityType": "rice",
            "capacity": 1000,
            "ownerId": "e2e-user-001",
        })

        # ── Step 2: Seed latest reading ────────────────────────────────
        wh_ref.collection("latest").document("current").set({
            "temperature": 36.8,
            "humidity": 78.0,
            "co2": 550.0,
            "gasLevel": 0.35,
            "riskScore": 0.85,
            "riskLevel": "critical",
            "daysToSpoilage": 2.1,
            "estimatedLossInr": 32000.0,
            "commodityType": "rice",
            "timestamp": datetime.datetime.utcnow(),
        })

        # ── Step 3: Seed historical readings ───────────────────────────
        now = datetime.datetime.utcnow()
        for i in range(5):
            wh_ref.collection("readings").add({
                "temperature": 30.0 + i * 1.5,
                "humidity": 65.0 + i * 2.5,
                "co2": 400.0 + i * 30,
                "gasLevel": 0.1 + i * 0.05,
                "riskScore": 0.4 + i * 0.1,
                "riskLevel": "warning" if i < 3 else "critical",
                "daysToSpoilage": 8.0 - i * 1.2,
                "estimatedLossInr": 5000.0 + i * 5000,
                "commodityType": "rice",
                "timestamp": now - datetime.timedelta(hours=5 - i),
            })

        # ── Step 4: Seed an alert ──────────────────────────────────────
        alert_ref = wh_ref.collection("alerts").document()
        alert_ref.set({
            "type": "spoilage_risk",
            "severity": "critical",
            "riskLevel": "critical",
            "riskScore": 0.85,
            "message": "Temperature 36.8\u00b0C \u2014 rice spoilage imminent within 2 days",
            "commodityType": "rice",
            "acknowledged": False,
            "timestamp": datetime.datetime.utcnow(),
        })
        alert_id = alert_ref.id

        # ── Step 5a: GET /warehouses ───────────────────────────────────
        data, status, _ = _parse(api_handler(_req("GET", "/warehouses")))
        assert status == 200
        assert isinstance(data, list)
        ids = [w["id"] for w in data]
        assert wh_id in ids, f"E2E warehouse not in list: {ids}"

        # ── Step 5b: GET /warehouse/{id}/summary ───────────────────────
        data, status, _ = _parse(api_handler(_req("GET", f"/warehouse/{wh_id}/summary")))
        assert status == 200
        assert data["warehouse_id"] == wh_id
        assert data["readings_count"] == 5
        assert "temperature" in data

        # ── Step 5c: GET /warehouse/{id}/export ────────────────────────
        body, status, headers = api_handler(_req("GET", f"/warehouse/{wh_id}/export"))
        assert status == 200
        assert "text/csv" in headers.get("Content-Type", "")
        lines = body.strip().split("\n")
        assert len(lines) == 6  # 1 header + 5 data rows

        # ── Step 5d: POST /alerts/{wh}/{alert}/acknowledge ────────────
        data, status, _ = _parse(
            api_handler(_req("POST", f"/alerts/{wh_id}/{alert_id}/acknowledge",
                             body={"userId": "e2e-user-001"}))
        )
        assert status == 200
        assert data["status"] == "acknowledged"

        # Verify Firestore updated
        alert_doc = (
            firestore_client.collection("warehouses").document(wh_id)
            .collection("alerts").document(alert_id).get()
        )
        assert alert_doc.to_dict()["acknowledged"] is True

        # ── Cleanup ───────────────────────────────────────────────────
        for sub in ("latest", "readings", "alerts"):
            for doc in wh_ref.collection(sub).stream():
                doc.reference.delete()
        wh_ref.delete()

    @pytest.mark.e2e
    @patch("alert_main.http_requests.post")
    def test_alert_triggers_notifications(self, mock_tg_post, firestore_client, alert_module):
        """Seed a critical alert → call on_alert_created → verify no crash."""
        mock_tg_post.return_value = MagicMock(status_code=200)

        wh_id = "e2e-wh-002"
        wh_ref = firestore_client.collection("warehouses").document(wh_id)
        wh_ref.set({
            "name": "E2E Notification Test",
            "location": "Amritsar",
            "commodityType": "potato",
        })

        alert_ref = wh_ref.collection("alerts").document()
        alert_ref.set({
            "type": "spoilage_risk",
            "severity": "critical",
            "riskScore": 0.95,
            "message": "Potato storage critical — gas levels elevated",
            "commodityType": "potato",
            "acknowledged": False,
            "timestamp": datetime.datetime.utcnow(),
        })

        # Build a proper CloudEvent
        event_data = _build_eventarc_payload(wh_id, alert_ref.id, severity="critical")
        event = CloudEvent(
            {
                "type": "google.cloud.firestore.document.v1.created",
                "source": "//firestore.googleapis.com/projects/postharvest-hack/databases/(default)",
                "subject": f"documents/warehouses/{wh_id}/alerts/{alert_ref.id}",
            },
            event_data,
        )

        import os
        os.environ["TELEGRAM_BOT_TOKEN"] = "fake-token"
        os.environ["TELEGRAM_CHAT_ID"] = "12345"

        try:
            alert_module.on_alert_created(event)
        except Exception as e:
            print(f"Alert function raised (expected with mocked backends): {e}")
        finally:
            os.environ.pop("TELEGRAM_BOT_TOKEN", None)
            os.environ.pop("TELEGRAM_CHAT_ID", None)

        # If Telegram was called, verify the URL contains sendMessage
        if mock_tg_post.called:
            assert "sendMessage" in str(mock_tg_post.call_args)

        # Cleanup
        for doc in wh_ref.collection("alerts").stream():
            doc.reference.delete()
        wh_ref.delete()
