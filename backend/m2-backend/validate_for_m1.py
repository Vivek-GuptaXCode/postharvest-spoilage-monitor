"""
Sensor data validation — no external dependencies.

Shared between M1's predict-spoilage Cloud Function and M2's REST API.
This is a copy from m2-backend/api-function/validate.py.

Usage:
    from validate import validate_sensor_payload
    clean_data, errors = validate_sensor_payload(raw_json_dict)
"""

import re

VALID_COMMODITIES = {"tomato", "potato", "banana", "rice", "onion"}
VALID_WAREHOUSE_PATTERN = r"^wh\d{3}$"

FIELD_RULES = {
    "warehouse_id":     {"type": str,   "required": True},
    "commodity_type":   {"type": str,   "required": True,  "allowed": VALID_COMMODITIES},
    "temperature":      {"type": float, "required": True,  "min": -40.0, "max": 80.0},
    "humidity":         {"type": float, "required": True,  "min": 0.0,   "max": 100.0},
    "co2":              {"type": float, "required": False, "min": 200.0, "max": 5000.0, "default": 400.0},
    "gas_level":        {"type": float, "required": False, "min": 0.0,   "max": 2000.0, "default": 0.0},
    "hours_in_storage": {"type": float, "required": False, "min": 0.0,   "max": 8760.0, "default": 0.0},
    "image_url":        {"type": str,   "required": False, "default": ""},
}


def validate_sensor_payload(data: dict | None) -> tuple[dict, list[str]]:
    """
    Validate and clean an incoming sensor JSON payload.

    Returns
    -------
    (clean_data, errors)
        clean_data : dict with validated + type-coerced values (empty if errors)
        errors     : list of human-readable error strings (empty if valid)
    """
    if not data or not isinstance(data, dict):
        return {}, ["Payload must be a non-empty JSON object."]

    errors: list[str] = []
    clean: dict = {}

    for field, rules in FIELD_RULES.items():
        value = data.get(field)

        # ── Missing ───────────────────────────────────────────────
        if value is None or value == "":
            if rules.get("required"):
                errors.append(f"Missing required field: '{field}'.")
                continue
            else:
                clean[field] = rules.get("default")
                continue

        # ── Type coercion ─────────────────────────────────────────
        expected_type = rules["type"]
        if expected_type is float:
            try:
                value = float(value)
            except (ValueError, TypeError):
                errors.append(f"Field '{field}' must be a number, got: {value!r}.")
                continue
        elif expected_type is str:
            value = str(value).strip()

        # ── Range check ───────────────────────────────────────────
        if expected_type is float:
            lo, hi = rules.get("min"), rules.get("max")
            if lo is not None and value < lo:
                errors.append(f"Field '{field}' = {value} is below minimum {lo}.")
                continue
            if hi is not None and value > hi:
                errors.append(f"Field '{field}' = {value} exceeds maximum {hi}.")
                continue

        # ── Allowed values ────────────────────────────────────────
        allowed = rules.get("allowed")
        if allowed and value not in allowed:
            errors.append(f"Field '{field}' = '{value}' not in allowed values: {sorted(allowed)}.")
            continue

        clean[field] = value

    # ── Warehouse ID format check ─────────────────────────────────
    wh_id = clean.get("warehouse_id", "")
    if wh_id and not re.match(VALID_WAREHOUSE_PATTERN, wh_id):
        errors.append(
            f"Field 'warehouse_id' = '{wh_id}' does not match pattern '{VALID_WAREHOUSE_PATTERN}'."
        )

    if errors:
        return {}, errors
    return clean, []
