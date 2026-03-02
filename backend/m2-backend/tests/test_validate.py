"""Unit tests for the shared validation module — no emulator needed.

validate_sensor_payload() returns (clean_data: dict, errors: list[str]).
  - On success: clean_data is a populated dict, errors is [].
  - On failure: clean_data is {}, errors is a non-empty list.

Valid commodities: tomato, potato, banana, rice, onion
Warehouse ID pattern: ^wh\\d{3}$  (e.g. wh001, wh002)
"""
import sys
import os
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'api-function'))
from validate import validate_sensor_payload

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

class TestValidateSensorPayload:
    """Tests for validate.validate_sensor_payload()."""

    def test_valid_payload_tomato(self):
        """All required + optional fields, valid commodity & warehouse format."""
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 30.0,
            "humidity": 65.0,
            "co2": 400.0,
            "gas_level": 0.1,
        }
        clean, errors = validate_sensor_payload(payload)
        assert errors == []
        assert clean["warehouse_id"] == "wh001"
        assert clean["commodity_type"] == "tomato"
        assert clean["temperature"] == 30.0

    def test_valid_payload_potato(self):
        payload = {
            "warehouse_id": "wh002",
            "commodity_type": "potato",
            "temperature": 4.5,
            "humidity": 96.0,
        }
        clean, errors = validate_sensor_payload(payload)
        assert errors == []
        assert clean["commodity_type"] == "potato"

    def test_missing_required_warehouse_id(self):
        payload = {
            "commodity_type": "tomato",
            "temperature": 30.0,
            "humidity": 65.0,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("warehouse_id" in e for e in errors)

    def test_missing_required_temperature(self):
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "humidity": 65.0,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("temperature" in e for e in errors)

    def test_missing_required_humidity(self):
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 25.0,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("humidity" in e for e in errors)

    def test_temperature_out_of_range_high(self):
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 120.0,  # max is 80
            "humidity": 65.0,
            "co2": 400.0,
            "gas_level": 0.1,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("temperature" in e.lower() for e in errors)

    def test_temperature_out_of_range_low(self):
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": -60.0,  # min is -40
            "humidity": 65.0,
            "co2": 400.0,
            "gas_level": 0.1,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("temperature" in e.lower() for e in errors)

    def test_humidity_out_of_range(self):
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 30.0,
            "humidity": 150.0,  # max is 100
            "co2": 400.0,
            "gas_level": 0.1,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("humidity" in e.lower() for e in errors)

    def test_invalid_commodity_type(self):
        """'plutonium' is not in {tomato, potato, banana, rice, onion}."""
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "plutonium",
            "temperature": 30.0,
            "humidity": 65.0,
            "co2": 400.0,
            "gas_level": 0.1,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("commodity" in e.lower() for e in errors)

    def test_wrong_type_temperature_string(self):
        """Temperature must be numeric; 'hot' should fail type coercion."""
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": "hot",
            "humidity": 65.0,
            "co2": 400.0,
            "gas_level": 0.1,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert len(errors) > 0

    def test_optional_co2_missing_gets_default(self):
        """co2 is optional (default 400.0). Omitting it should still pass."""
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 30.0,
            "humidity": 65.0,
            "gas_level": 0.1,
        }
        clean, errors = validate_sensor_payload(payload)
        assert errors == []
        assert clean["co2"] == 400.0  # default value

    def test_optional_gas_level_missing_gets_default(self):
        """gas_level is optional (default 0.0)."""
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": 25.0,
            "humidity": 90.0,
        }
        clean, errors = validate_sensor_payload(payload)
        assert errors == []
        assert clean["gas_level"] == 0.0

    def test_optional_hours_in_storage_default(self):
        """hours_in_storage defaults to 0.0 when omitted."""
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "rice",
            "temperature": 18.0,
            "humidity": 58.0,
        }
        clean, errors = validate_sensor_payload(payload)
        assert errors == []
        assert clean["hours_in_storage"] == 0.0

    def test_none_payload(self):
        clean, errors = validate_sensor_payload(None)
        assert clean == {}
        assert len(errors) > 0

    def test_empty_dict_payload(self):
        clean, errors = validate_sensor_payload({})
        assert clean == {}
        assert len(errors) > 0

    def test_warehouse_id_format_invalid(self):
        """Warehouse ID must match ^wh\\d{3}$ — 'wh-001' should fail."""
        payload = {
            "warehouse_id": "wh-001",
            "commodity_type": "tomato",
            "temperature": 25.0,
            "humidity": 80.0,
        }
        clean, errors = validate_sensor_payload(payload)
        assert clean == {}
        assert any("warehouse_id" in e for e in errors)

    def test_numeric_string_temperature_coerced(self):
        """String '25.5' should be coerced to float 25.5 successfully."""
        payload = {
            "warehouse_id": "wh001",
            "commodity_type": "tomato",
            "temperature": "25.5",
            "humidity": "80.0",
        }
        clean, errors = validate_sensor_payload(payload)
        assert errors == []
        assert clean["temperature"] == 25.5
        assert clean["humidity"] == 80.0

    def test_all_five_commodities_accepted(self):
        """Each valid commodity should pass validation."""
        for commodity in ("tomato", "potato", "banana", "rice", "onion"):
            payload = {
                "warehouse_id": "wh001",
                "commodity_type": commodity,
                "temperature": 20.0,
                "humidity": 70.0,
            }
            clean, errors = validate_sensor_payload(payload)
            assert errors == [], f"Failed for commodity={commodity}: {errors}"