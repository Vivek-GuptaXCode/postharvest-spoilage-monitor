"""Integration tests for the REST API Cloud Function.

Requires: firebase emulators:start (Firestore on localhost:8080)
Run with: python -m pytest tests/test_api_function.py -m integration -v
"""
import pytest
import json
from unittest.mock import MagicMock

from main import api_handler  # api-function/ is on sys.path via conftest


def _make_request(method="GET", path="/", body=None, headers=None):
    """Build a fake Flask request object matching functions-framework convention."""
    req = MagicMock()
    req.method = method
    req.path = path
    req.get_json.return_value = body or {}
    req.args = {}
    req.headers = headers or {"Origin": "http://localhost:3000"}
    return req


def _parse_response(resp):
    """Unpack api_handler's (json_str, status, headers) tuple."""
    body, status, _ = resp
    data = json.loads(body) if isinstance(body, str) else body
    return data, status


# ═══════════════════════════════════════════════════════════════════════
# Health
# ═══════════════════════════════════════════════════════════════════════

class TestHealthEndpoint:
    def test_health_returns_200(self):
        data, status = _parse_response(api_handler(_make_request("GET", "/health")))
        assert status == 200
        assert data["status"] == "healthy"

    def test_health_has_timestamp(self):
        data, _ = _parse_response(api_handler(_make_request("GET", "/health")))
        assert "timestamp" in data


# ═══════════════════════════════════════════════════════════════════════
# Warehouses list
# ═══════════════════════════════════════════════════════════════════════

class TestWarehousesEndpoint:
    @pytest.mark.integration
    def test_list_warehouses_returns_list(self, clean_firestore):
        data, status = _parse_response(api_handler(_make_request("GET", "/warehouses")))
        assert status == 200
        assert isinstance(data, list)

    @pytest.mark.integration
    def test_list_warehouses_with_seeded_data(self, seed_warehouse):
        data, status = _parse_response(api_handler(_make_request("GET", "/warehouses")))
        assert status == 200
        assert isinstance(data, list)
        assert len(data) >= 1
        ids = [w.get("id") for w in data]
        assert seed_warehouse in ids

    @pytest.mark.integration
    def test_warehouse_has_latest_subfield(self, seed_warehouse):
        data, _ = _parse_response(api_handler(_make_request("GET", "/warehouses")))
        wh = next(w for w in data if w["id"] == seed_warehouse)
        assert wh["latest"] is not None
        assert "temperature" in wh["latest"]
        assert "riskLevel" in wh["latest"]


# ═══════════════════════════════════════════════════════════════════════
# Warehouse summary
# ═══════════════════════════════════════════════════════════════════════

class TestWarehouseSummaryEndpoint:
    @pytest.mark.integration
    def test_summary_returns_stats(self, seed_warehouse):
        data, status = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/summary"))
        )
        assert status == 200
        assert data["warehouse_id"] == seed_warehouse
        assert data["readings_count"] >= 1
        assert "temperature" in data

    @pytest.mark.integration
    def test_summary_has_min_max_avg(self, seed_warehouse):
        data, _ = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/summary"))
        )
        for field in ("temperature", "humidity", "risk_score"):
            assert "avg" in data[field]
            assert "min" in data[field]
            assert "max" in data[field]

    @pytest.mark.integration
    def test_summary_nonexistent_warehouse(self, clean_firestore):
        _, status = _parse_response(
            api_handler(_make_request("GET", "/warehouse/nonexistent-999/summary"))
        )
        assert status == 404


# ═══════════════════════════════════════════════════════════════════════
# Export
# ═══════════════════════════════════════════════════════════════════════

class TestExportEndpoint:
    @pytest.mark.integration
    def test_export_returns_csv(self, seed_warehouse):
        body, status, headers = api_handler(
            _make_request("GET", f"/warehouse/{seed_warehouse}/export")
        )
        assert status == 200
        assert "text/csv" in headers.get("Content-Type", "")
        assert "timestamp" in body  # CSV header row

    @pytest.mark.integration
    def test_export_no_readings_returns_404(self, clean_firestore):
        """Export for a warehouse with no readings → 404 or empty."""
        # Seed a warehouse with no readings in the last 24h
        clean_firestore.collection("warehouses").document("wh999").set(
            {"name": "Empty", "commodityType": "onion"}
        )
        _, status, _ = api_handler(
            _make_request("GET", "/warehouse/wh999/export")
        )
        assert status == 404


# ═══════════════════════════════════════════════════════════════════════
# Acknowledge alert
# ═══════════════════════════════════════════════════════════════════════

class TestAcknowledgeEndpoint:
    @pytest.mark.integration
    def test_acknowledge_alert(self, seed_alert, firestore_client):
        wh_id, alert_id = seed_alert
        req = _make_request(
            "POST", f"/alerts/{wh_id}/{alert_id}/acknowledge",
            body={"userId": "test-user-001"},
        )
        data, status = _parse_response(api_handler(req))
        assert status == 200
        assert data["status"] == "acknowledged"

        # Verify Firestore was updated
        alert_doc = (
            firestore_client.collection("warehouses").document(wh_id)
            .collection("alerts").document(alert_id).get()
        )
        assert alert_doc.exists
        assert alert_doc.to_dict()["acknowledged"] is True

    @pytest.mark.integration
    def test_acknowledge_nonexistent_alert(self, seed_warehouse):
        req = _make_request(
            "POST", f"/alerts/{seed_warehouse}/fake-alert-999/acknowledge",
            body={"userId": "test-user-001"},
        )
        _, status = _parse_response(api_handler(req))
        assert status == 404


# ═══════════════════════════════════════════════════════════════════════
# 404 for unknown routes
# ═══════════════════════════════════════════════════════════════════════

class TestRouting:
    def test_unknown_path_returns_404(self):
        _, status = _parse_response(api_handler(_make_request("GET", "/no-such-route")))
        assert status == 404

    def test_cors_preflight(self):
        resp = api_handler(_make_request("OPTIONS", "/health"))
        _, status, headers = resp


# ═══════════════════════════════════════════════════════════════════════
# Zone endpoints (Part 6)
# ═══════════════════════════════════════════════════════════════════════

class TestListZonesEndpoint:
    @pytest.mark.integration
    def test_list_zones_returns_list(self, seed_warehouse):
        data, status = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/zones"))
        )
        assert status == 200
        assert isinstance(data, list)
        assert len(data) == 10  # 10 zones seeded

    @pytest.mark.integration
    def test_zones_have_id_and_latest(self, seed_warehouse):
        data, _ = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/zones"))
        )
        zone = data[0]
        assert "id" in zone
        assert zone["id"].startswith("zone-")
        assert "latest" in zone
        assert zone["latest"] is not None
        assert "temperature" in zone["latest"]

    @pytest.mark.integration
    def test_list_zones_nonexistent_warehouse(self, clean_firestore):
        _, status = _parse_response(
            api_handler(_make_request("GET", "/warehouse/nonexistent-999/zones"))
        )
        assert status == 404


class TestZoneSummaryEndpoint:
    @pytest.mark.integration
    def test_zone_summary_returns_data(self, seed_warehouse):
        """Zone summary — zone has latest but may not have readings from last 24h."""
        data, status = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/zone/zone-A/summary"))
        )
        assert status == 200
        assert data["zone_id"] == "zone-A"
        assert data["warehouse_id"] == seed_warehouse
        assert "commodity_type" in data

    @pytest.mark.integration
    def test_zone_summary_nonexistent_zone(self, seed_warehouse):
        _, status = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/zone/zone-Z/summary"))
        )
        # zone-Z doesn't exist in seed data
        assert status == 404

    @pytest.mark.integration
    def test_zone_summary_invalid_zone_id_format(self, seed_warehouse):
        _, status = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/zone/bad-id/summary"))
        )
        assert status == 400

    @pytest.mark.integration
    def test_zone_summary_with_readings(self, seed_warehouse, firestore_client):
        """Seed readings into a zone and verify stats are returned."""
        import datetime
        zone_ref = (
            firestore_client.collection("warehouses").document(seed_warehouse)
            .collection("zones").document("zone-A")
        )
        now = datetime.datetime.utcnow()
        for i in range(3):
            zone_ref.collection("readings").add({
                "temperature": 25.0 + i,
                "humidity": 60.0 + i * 5,
                "riskScore": 0.3 + i * 0.1,
                "daysToSpoilage": 6.0 - i,
                "timestamp": now - datetime.timedelta(hours=2 - i),
            })
        data, status = _parse_response(
            api_handler(_make_request("GET", f"/warehouse/{seed_warehouse}/zone/zone-A/summary"))
        )
        assert status == 200
        assert data["readings_count"] == 3
        assert "temperature" in data
        assert data["temperature"]["min"] == 25.0
        assert data["temperature"]["max"] == 27.0
        assert status == 204
        assert headers["Access-Control-Allow-Origin"] == "*"