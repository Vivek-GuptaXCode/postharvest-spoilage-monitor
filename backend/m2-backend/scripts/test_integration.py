"""
Integration tests for the PostHarvest system.

Tests M1's predict-spoilage Cloud Function and M2's postharvest-api Cloud
Function end-to-end.  Validates the full pipeline: sensor → prediction → API.

Run:
    pytest test_integration.py -v --tb=short

Environment variables:
    PREDICT_URL  — M1's predict-spoilage Cloud Function URL
    API_URL      — M2's postharvest-api Cloud Function URL

If env vars are not set, replace the placeholder URLs below.
"""

import os
import time

import pytest
import requests

PREDICT_URL = os.environ.get("PREDICT_URL", "https://REPLACE_WITH_PREDICT_SPOILAGE_URL")
API_URL     = os.environ.get("API_URL", "https://REPLACE_WITH_API_URL")


# ═══════════════════════════════════════════════════════════════════════
# Sensor Ingestion (M1's Cloud Function)
# ═══════════════════════════════════════════════════════════════════════

class TestSensorIngestion:
    """Tests against M1's predict-spoilage Cloud Function.

    Validates that the function:
      - Accepts valid sensor payloads and returns predictions
      - Rejects incomplete payloads with 400 status
      - Returns correct response fields (status, risk_level, risk_score,
        days_to_spoilage, timestamp)
      - Handles burst traffic
    """

    def _post(self, payload: dict) -> requests.Response:
        return requests.post(PREDICT_URL, json=payload, timeout=15)

    def test_valid_reading_returns_prediction(self):
        """A complete sensor reading should produce a valid prediction."""
        r = self._post({
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 28.5,
            "humidity": 92.3,
            "co2": 650,
            "gas_level": 120,
            "hours_in_storage": 48,
        })
        assert r.status_code == 200
        data = r.json()
        assert data["status"] == "ok"
        assert data["risk_level"] in ("low", "medium", "high", "critical")
        assert 0 <= data["risk_score"] <= 100
        assert data["days_to_spoilage"] >= 0

    def test_missing_temperature_returns_400(self):
        """Missing required field 'temperature' should return 400."""
        r = self._post({"warehouse_id": "wh001", "humidity": 92.3})
        assert r.status_code == 400

    def test_missing_humidity_returns_400(self):
        """Missing required field 'humidity' should return 400."""
        r = self._post({"warehouse_id": "wh001", "temperature": 20.0})
        assert r.status_code == 400

    def test_extreme_heat_returns_critical(self):
        """Extreme conditions (55°C, 10% RH) should return elevated risk."""
        r = self._post({
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 55.0,
            "humidity": 10.0,
            "hours_in_storage": 100,
        })
        assert r.status_code == 200
        assert r.json()["risk_level"] in ("medium", "high", "critical")

    def test_optimal_conditions_returns_low_risk(self):
        """Optimal tomato storage (13.5°C, 90% RH) should return low or medium risk."""
        r = self._post({
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 13.5,
            "humidity": 90.0,
            "hours_in_storage": 1,
        })
        assert r.status_code == 200
        assert r.json()["risk_level"] in ("low", "medium")

    def test_different_commodity(self):
        """Potato at optimal conditions should return low or medium risk."""
        r = self._post({
            "warehouse_id": "wh002",
            "commodity_type": "potato",
            "temperature": 4.5,
            "humidity": 96.0,
        })
        assert r.status_code == 200
        assert r.json()["risk_level"] in ("low", "medium")

    def test_optional_fields_have_defaults(self):
        """co2, gas_level, hours_in_storage should default gracefully when omitted."""
        r = self._post({
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 20.0,
            "humidity": 80.0,
        })
        assert r.status_code == 200

    def test_response_has_all_expected_fields(self):
        """Response JSON must include all fields expected by M4's Flutter app."""
        r = self._post({
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 25.0,
            "humidity": 70.0,
        })
        data = r.json()
        for key in ("status", "risk_level", "risk_score", "days_to_spoilage", "timestamp"):
            assert key in data, f"Missing key: {key}"

    def test_rapid_fire_10_requests(self):
        """Ensure the function handles burst traffic (10 rapid requests)."""
        results = []
        for i in range(10):
            r = self._post({
                "warehouse_id": "wh001",
                "commodity_type": "tomato",
                "temperature": 20.0 + i * 2,
                "humidity": 80.0,
            })
            results.append(r.status_code)
        assert all(code == 200 for code in results)


# ═══════════════════════════════════════════════════════════════════════
# REST API (M2's Cloud Function)
# ═══════════════════════════════════════════════════════════════════════

class TestRestAPI:
    """Tests against M2's postharvest-api Cloud Function.

    Validates all REST endpoints that M4's Flutter app depends on.
    """

    def test_health(self):
        """GET /health should return status=healthy."""
        r = requests.get(f"{API_URL}/health", timeout=15)
        assert r.status_code == 200
        assert r.json()["status"] == "healthy"

    def test_list_warehouses(self):
        """GET /warehouses should return a list with id and latest fields."""
        r = requests.get(f"{API_URL}/warehouses", timeout=15)
        assert r.status_code == 200
        data = r.json()
        assert isinstance(data, list)
        if data:
            assert "id" in data[0]
            assert "latest" in data[0]

    def test_warehouse_summary(self):
        """GET /warehouse/wh001/summary should return warehouse_id in response."""
        r = requests.get(f"{API_URL}/warehouse/wh001/summary", timeout=15)
        assert r.status_code == 200
        data = r.json()
        assert "warehouse_id" in data

    def test_warehouse_not_found(self):
        """GET /warehouse/nonexistent/summary should return 404."""
        r = requests.get(f"{API_URL}/warehouse/nonexistent/summary", timeout=15)
        assert r.status_code == 404

    def test_export_csv(self):
        """GET /warehouse/wh001/export returns CSV or 404 if no data."""
        r = requests.get(f"{API_URL}/warehouse/wh001/export?hours=24", timeout=15)
        # 404 is valid if no readings exist yet
        assert r.status_code in (200, 404)
        if r.status_code == 200:
            assert "text/csv" in r.headers.get("Content-Type", "")

    def test_unknown_route_returns_404(self):
        """Unknown routes should return 404 with an error message."""
        r = requests.get(f"{API_URL}/nonexistent", timeout=15)
        assert r.status_code == 404


# ═══════════════════════════════════════════════════════════════════════
# End-to-End Flow
# ═══════════════════════════════════════════════════════════════════════

class TestEndToEnd:
    """Verifies the full sensor → prediction → API pipeline.

    Posts a reading to M1's function, waits for Firestore propagation,
    then checks M2's API for the data.
    """

    def test_sensor_to_summary(self):
        """Post a reading, then verify it appears in the warehouse summary."""
        # Step 1: Send a sensor reading via M1's Cloud Function
        r = requests.post(PREDICT_URL, json={
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 30.0,
            "humidity": 50.0,
        }, timeout=15)
        assert r.status_code == 200

        # Step 2: Wait for Firestore propagation
        time.sleep(3)

        # Step 3: Fetch summary via M2's API — should have at least 1 reading
        r = requests.get(f"{API_URL}/warehouse/wh001/summary", timeout=15)
        assert r.status_code == 200
        data = r.json()
        assert data.get("readings_count", 0) >= 1
