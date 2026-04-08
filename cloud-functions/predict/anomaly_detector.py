"""
IoT Payload Anomaly Detector — flags corrupted or implausible sensor data.

Four detection layers (all O(1), no I/O):
  1. Physical bounds      – impossible sensor values (hardware fault / garbled decrypt)
  2. Commodity plausibility – far outside commodity-specific optimal band
  3. Inter-sensor physics  – contradictory channel combinations
  4. Flatline / stuck      – all channels at identical or zero values

Returns:
    {
      "is_anomalous": bool,
      "anomaly_score": float 0-1,   # 0 = normal, 1 = certainly corrupt
      "anomaly_flags": ["flag_name", ...]
    }
"""

# ── Absolute physical bounds (any commodity) ──────────────────────────
PHYSICAL_BOUNDS = {
    "temperature": (-40.0, 80.0),   # °C  (even cold-chain rarely below -30)
    "humidity":    (0.0, 100.0),     # %RH
    "co2":         (0.0, 10000.0),   # ppm (ambient ~420, max indoor ~5000)
    "gas_level":   (0.0, 5000.0),    # arbitrary sensor units
}

# How many multiples of the optimal-range width we tolerate before
# flagging as "implausible for this commodity".  Generous to avoid
# false positives on legitimate spikes.
_PLAUSIBILITY_MARGIN = 3.0


def detect_anomalies(data: dict, commodity: str, thresholds: dict) -> dict:
    """Run all anomaly checks on a single sensor reading.

    Args:
        data:        dict with keys temperature, humidity, co2, gas_level
        commodity:   e.g. "tomato", "potato"
        thresholds:  the global THRESHOLDS dict (commodity → optimal ranges)

    Returns:
        dict with is_anomalous (bool), anomaly_score (0-1), anomaly_flags (list)
    """
    flags: list[str] = []
    scores: list[float] = []  # per-check severity (0-1)

    temp = float(data.get("temperature", 0))
    hum  = float(data.get("humidity", 0))
    co2  = float(data.get("co2", 400))
    gas  = float(data.get("gas_level", 0))

    # ── 1. Physical bounds ────────────────────────────────────────────
    for field, (lo, hi) in PHYSICAL_BOUNDS.items():
        val = float(data.get(field, 0))
        if val < lo or val > hi:
            flags.append(f"{field}_out_of_physical_range")
            scores.append(1.0)  # certainly corrupt

    # ── 2. Commodity-aware plausibility ───────────────────────────────
    th = thresholds.get(commodity, thresholds.get("tomato", {}))
    if th:
        opt_temp_min = th.get("optimal_temp_min", 0)
        opt_temp_max = th.get("optimal_temp_max", 40)
        opt_rh_min   = th.get("optimal_rh_min", 30)
        opt_rh_max   = th.get("optimal_rh_max", 100)

        temp_width = max(opt_temp_max - opt_temp_min, 1)
        rh_width   = max(opt_rh_max - opt_rh_min, 1)

        # Distance outside the optimal band, in units of band-width
        if temp < opt_temp_min:
            dev = (opt_temp_min - temp) / temp_width
        elif temp > opt_temp_max:
            dev = (temp - opt_temp_max) / temp_width
        else:
            dev = 0.0
        if dev > _PLAUSIBILITY_MARGIN:
            flags.append("temperature_implausible_for_commodity")
            scores.append(min(dev / (_PLAUSIBILITY_MARGIN * 2), 1.0))

        if hum < opt_rh_min:
            dev = (opt_rh_min - hum) / rh_width
        elif hum > opt_rh_max:
            dev = (hum - opt_rh_max) / rh_width
        else:
            dev = 0.0
        if dev > _PLAUSIBILITY_MARGIN:
            flags.append("humidity_implausible_for_commodity")
            scores.append(min(dev / (_PLAUSIBILITY_MARGIN * 2), 1.0))

    # ── 3. Inter-sensor physics ───────────────────────────────────────
    # Sub-zero temp + near-100% humidity + high gas ⇒ likely garbled
    if temp < -10 and hum > 95 and gas > 500:
        flags.append("contradictory_sensor_combination")
        scores.append(0.9)

    # Very high CO₂ with very low temperature is physically unlikely
    # (respiration drops near freezing)
    if temp < -5 and co2 > 3000:
        flags.append("co2_temp_contradiction")
        scores.append(0.8)

    # ── 4. Flatline / stuck sensor ────────────────────────────────────
    channels = [temp, hum, co2, gas]
    # All exactly zero → sensor dead / no data
    if all(v == 0.0 for v in channels):
        flags.append("all_channels_zero")
        scores.append(1.0)
    # All identical non-zero → stuck ADC
    elif len(set(round(v, 2) for v in channels)) == 1:
        flags.append("all_channels_identical")
        scores.append(0.85)
    # Two critical channels stuck at exactly the same round value
    elif temp == hum and temp == round(temp):
        flags.append("temp_humidity_stuck_same_value")
        scores.append(0.6)

    # ── Aggregate ─────────────────────────────────────────────────────
    anomaly_score = round(max(scores) if scores else 0.0, 3)
    is_anomalous = anomaly_score > 0.0

    return {
        "is_anomalous":  is_anomalous,
        "anomaly_score": anomaly_score,
        "anomaly_flags": flags,
    }
