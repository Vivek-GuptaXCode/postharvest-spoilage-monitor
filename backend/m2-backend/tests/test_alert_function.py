"""Integration tests for the alert notification Cloud Function.

Tests that on_alert_created correctly reads an alert doc and attempts
to send notifications.  Twilio/Telegram HTTP calls are mocked so these
tests can run offline.

Requires: firebase emulators:start (Firestore on localhost:8080)
"""
import pytest
from unittest.mock import patch, MagicMock
from cloudevents.http import CloudEvent


# ═══════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════

def _build_eventarc_payload(warehouse_id: str, alert_id: str,
                            severity: str = "critical",
                            message: str = "Temperature 36.8°C — tomato spoilage imminent") -> dict:
    """Build a Firestore Eventarc-style payload matching the structure
    that _extract_fields() in alert-function/main.py expects.

    Structure: data.value.name + data.value.fields
    """
    return {
        "value": {
            "name": (
                f"projects/postharvest-hack/databases/(default)/documents/"
                f"warehouses/{warehouse_id}/alerts/{alert_id}"
            ),
            "fields": {
                "severity":     {"stringValue": severity},
                "message":      {"stringValue": message},
                "type":         {"stringValue": "spoilage_risk"},
                "acknowledged": {"booleanValue": False},
            },
        }
    }


def _make_cloud_event(warehouse_id: str, alert_id: str, **kwargs) -> CloudEvent:
    """Create a real CloudEvent object with Eventarc-style data."""
    attributes = {
        "type": "google.cloud.firestore.document.v1.created",
        "source": "//firestore.googleapis.com/projects/postharvest-hack/databases/(default)",
        "subject": f"documents/warehouses/{warehouse_id}/alerts/{alert_id}",
    }
    data = _build_eventarc_payload(warehouse_id, alert_id, **kwargs)
    return CloudEvent(attributes, data)


# ═══════════════════════════════════════════════════════════════════════
# TESTS
# ═══════════════════════════════════════════════════════════════════════

class TestAlertFunction:

    @pytest.mark.integration
    @patch("alert_main.http_requests.post")
    @patch("alert_main.TELEGRAM_CHAT_ID", "12345")
    @patch("alert_main.TELEGRAM_TOKEN", "fake-token")
    def test_critical_alert_sends_telegram(self, mock_post, seed_alert, alert_module):
        """Critical alert → Telegram sendMessage should be called."""
        mock_post.return_value = MagicMock(status_code=200)

        wh_id, alert_id = seed_alert
        event = _make_cloud_event(wh_id, alert_id, severity="critical")

        alert_module.on_alert_created(event)

        assert mock_post.called
        call_url = str(mock_post.call_args)
        assert "sendMessage" in call_url

    @pytest.mark.integration
    @patch("alert_main.http_requests.post")
    @patch("alert_main.TELEGRAM_CHAT_ID", "12345")
    @patch("alert_main.TELEGRAM_TOKEN", "fake-token")
    def test_warning_alert_sends_telegram(self, mock_post, seed_alert, alert_module):
        """Warning-level alerts should also trigger notifications."""
        mock_post.return_value = MagicMock(status_code=200)

        wh_id, alert_id = seed_alert
        event = _make_cloud_event(wh_id, alert_id, severity="warning")

        alert_module.on_alert_created(event)

        assert mock_post.called

    @pytest.mark.integration
    @patch("alert_main.http_requests.post")
    @patch("alert_main.TELEGRAM_CHAT_ID", "12345")
    @patch("alert_main.TELEGRAM_TOKEN", "fake-token")
    def test_low_severity_skips_notification(self, mock_post, seed_alert, alert_module):
        """Severity below warning/critical → no notification sent."""
        mock_post.return_value = MagicMock(status_code=200)

        wh_id, alert_id = seed_alert
        event = _make_cloud_event(wh_id, alert_id, severity="info")

        alert_module.on_alert_created(event)

        assert not mock_post.called

    @pytest.mark.integration
    @patch("alert_main.http_requests.post")
    def test_extract_fields_parses_warehouse_id(self, mock_post, alert_module):
        """_extract_fields correctly pulls the warehouse ID from the doc path."""
        mock_post.return_value = MagicMock(status_code=200)

        event = _make_cloud_event("wh042", "alert-xyz", severity="critical")
        fields = alert_module._extract_fields(event.data)

        assert fields["warehouse_id"] == "wh042"
        assert fields["severity"] == "critical"
        assert fields["type"] == "spoilage_risk"

    @pytest.mark.integration
    @patch("alert_main.ALERT_PHONES", ["+911234567890"])
    @patch("alert_main.TELEGRAM_CHAT_ID", "12345")
    @patch("alert_main.TELEGRAM_TOKEN", "fake-token")
    @patch("alert_main.http_requests.post")
    @patch("alert_main._get_twilio")
    def test_sms_sent_via_twilio(self, mock_get_twilio, mock_post, seed_alert, alert_module):
        """When Twilio is configured, SMS should be sent."""
        mock_post.return_value = MagicMock(status_code=200)

        mock_client = MagicMock()
        mock_client.messages.create.return_value = MagicMock(sid="SM_FAKE")
        mock_get_twilio.return_value = mock_client

        wh_id, alert_id = seed_alert
        event = _make_cloud_event(wh_id, alert_id, severity="critical")

        alert_module.on_alert_created(event)

        mock_client.messages.create.assert_called_once()

    @pytest.mark.integration
    @patch("alert_main.TELEGRAM_CHAT_ID", "")
    @patch("alert_main.TELEGRAM_TOKEN", "")
    @patch("alert_main.ALERT_PHONES", [])
    @patch("alert_main.http_requests.post")
    def test_no_crash_without_credentials(self, mock_post, alert_module):
        """Function should not crash when Twilio/Telegram env vars are missing."""
        event = _make_cloud_event("wh001", "alert-001", severity="critical")

        # Should not raise
        alert_module.on_alert_created(event)
