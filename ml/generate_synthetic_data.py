import os
import numpy as np
import pandas as pd
from datetime import datetime, timedelta

COMMODITY_PROFILES = {
    "tomato":  {"optimal_temp": (12, 15), "optimal_rh": (85, 95),
                "shelf_life_days_optimal": 14,  "shelf_life_days_worst": 2,
                "ethylene_sensitive": True,  "respiration_rate": "moderate"},
    "potato":  {"optimal_temp": (4, 5),   "optimal_rh": (95, 98),
                "shelf_life_days_optimal": 180, "shelf_life_days_worst": 30,
                "ethylene_sensitive": False, "respiration_rate": "low"},
    "banana":  {"optimal_temp": (13, 14), "optimal_rh": (90, 95),
                "shelf_life_days_optimal": 21,  "shelf_life_days_worst": 3,
                "ethylene_sensitive": True,  "respiration_rate": "high"},
    "rice":    {"optimal_temp": (15, 20), "optimal_rh": (50, 65),
                "shelf_life_days_optimal": 365, "shelf_life_days_worst": 90,
                "ethylene_sensitive": False, "respiration_rate": "very_low"},
    "onion":   {"optimal_temp": (0, 2),   "optimal_rh": (65, 70),
                "shelf_life_days_optimal": 180, "shelf_life_days_worst": 20,
                "ethylene_sensitive": False, "respiration_rate": "low"},
}


def generate_sensor_timeseries(
    commodity: str = "tomato",
    duration_hours: int = 168,        # 7 days
    reading_interval_sec: int = 30,
    scenario: str = "degrading",
    seed: int = 42,
) -> pd.DataFrame:
    """
    Scenarios
    ---------
    optimal      : stable near-optimal conditions → low risk throughout
    degrading    : gradual temperature rise / humidity drop (cooling failure)
    shock        : sudden temperature spike at ~60 % of the timeline
    fluctuating  : day/night cycle with poor insulation
    """
    np.random.seed(seed)
    profile = COMMODITY_PROFILES[commodity]
    n = int(duration_hours * 3600 / reading_interval_sec)
    t = np.arange(n)
    hours = t * reading_interval_sec / 3600

    opt_temp_mid = np.mean(profile["optimal_temp"])
    opt_rh_mid   = np.mean(profile["optimal_rh"])

    # --- Temperature & Humidity by scenario ---
    if scenario == "optimal":
        temp = opt_temp_mid + np.random.normal(0, 0.5, n)
        humidity = opt_rh_mid + np.random.normal(0, 1.5, n)

    elif scenario == "degrading":
        temp_drift = np.linspace(0, 15, n)
        temp = opt_temp_mid + temp_drift + np.random.normal(0, 0.8, n)
        rh_drift = np.linspace(0, -20, n)
        humidity = opt_rh_mid + rh_drift + np.random.normal(0, 2, n)

    elif scenario == "shock":
        sp = int(0.6 * n)
        temp = np.concatenate([
            opt_temp_mid + np.random.normal(0, 0.5, sp),
            opt_temp_mid + 18 + np.random.normal(0, 1.5, n - sp),
        ])
        humidity = np.concatenate([
            opt_rh_mid + np.random.normal(0, 1.5, sp),
            opt_rh_mid - 25 + np.random.normal(0, 3, n - sp),
        ])

    elif scenario == "fluctuating":
        day_cycle = 8 * np.sin(2 * np.pi * hours / 24)
        temp = opt_temp_mid + 5 + day_cycle + np.random.normal(0, 1, n)
        rh_cycle = -10 * np.sin(2 * np.pi * hours / 24)
        humidity = opt_rh_mid - 5 + rh_cycle + np.random.normal(0, 2, n)

    else:
        raise ValueError(f"Unknown scenario: {scenario}")

    # --- Derived channels ---
    base_co2 = 400
    co2 = base_co2 + (temp - opt_temp_mid) * 30 + np.random.normal(0, 20, n)
    co2 = np.clip(co2, 300, 2000)

    cumulative_stress = np.cumsum(
        np.maximum(temp - profile["optimal_temp"][1], 0)
    ) / 3600
    gas_level = 50 + cumulative_stress * 5 + np.random.normal(0, 10, n)
    gas_level = np.clip(gas_level, 0, 1000)
    humidity = np.clip(humidity, 20, 100)

    # --- Spoilage labels ---
    shelf_life_remaining = (
        profile["shelf_life_days_optimal"]
        - cumulative_stress * profile["shelf_life_days_optimal"]
          / (profile["shelf_life_days_optimal"] * 5)
        - hours / 24
    )

    # ── Realistic label noise ─────────────────────────────────────
    # Real-world spoilage depends on unobserved factors (microbial load,
    # produce maturity, packaging quality).
    #
    # KEY INSIGHT: shelf-life noise propagates to risk_score as:
    #   σ_score = σ_days / shelf_life_optimal × 100
    # So we target a FIXED ~2 pts σ on risk_score by computing:
    #   σ_days = 0.02 × shelf_life_optimal  (capped at 1.5 days)
    #
    # This gives consistent noise across all commodities:
    #   Tomato  (14 d): σ = 0.28 d → 2.0 pts   ✓
    #   Banana  (21 d): σ = 0.42 d → 2.0 pts   ✓
    #   Potato (180 d): σ = 1.50 d → 0.8 pts   ✓ (capped)
    #   Rice   (365 d): σ = 1.50 d → 0.4 pts   ✓ (capped)
    #
    # No additional noise is added to risk_score — shelf-life noise
    # is the SOLE source of label uncertainty.  Adding a second noise
    # layer caused ±5 pt effective noise on short-shelf-life crops,
    # creating an 89 % accuracy ceiling in v4.
    noise_std_days = min(0.02 * profile["shelf_life_days_optimal"], 1.5)
    noise_days = np.random.normal(0, noise_std_days, n)
    shelf_life_remaining += noise_days
    shelf_life_remaining = np.clip(
        shelf_life_remaining, 0, profile["shelf_life_days_optimal"]
    )

    risk_score = 100 * (
        1 - shelf_life_remaining / profile["shelf_life_days_optimal"]
    )
    risk_score = np.clip(risk_score, 0, 100)
    risk_level = pd.cut(
        risk_score,
        bins=[-1, 25, 50, 75, 100],
        labels=["low", "medium", "high", "critical"],
    )

    timestamps = [
        datetime(2026, 1, 1) + timedelta(seconds=int(i * reading_interval_sec))
        for i in range(n)
    ]

    return pd.DataFrame({
        "timestamp":         timestamps,
        "temperature":       np.round(temp, 2),
        "humidity":          np.round(humidity, 2),
        "co2":               np.round(co2, 1),
        "gas_level":         np.round(gas_level, 1),
        "commodity_type":    commodity,
        "hours_in_storage":  np.round(hours, 2),
        "days_to_spoilage":  np.round(shelf_life_remaining, 2),
        "risk_score":        np.round(risk_score, 2),
        "risk_level":        risk_level,
        "scenario":          scenario,
    })


# ── Main ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    frames = []
    for commodity in COMMODITY_PROFILES:
        for scenario in ["optimal", "degrading", "shock", "fluctuating"]:
            for variant_seed in range(3):
                df = generate_sensor_timeseries(
                    commodity=commodity,
                    scenario=scenario,
                    seed=variant_seed * 100 + hash(scenario) % 100,
                )
                frames.append(df)

    dataset = pd.concat(frames, ignore_index=True)

    # ── Class balancing via downsampling ──────────────────────────
    # Downsample every class to the size of the smallest class.
    # This guarantees perfect 25/25/25/25 % balance.
    min_class_size = dataset["risk_level"].value_counts().min()
    balanced_frames = []
    for level in ["low", "medium", "high", "critical"]:
        subset = dataset[dataset["risk_level"] == level]
        balanced_frames.append(
            subset.sample(n=min_class_size, random_state=42)
        )
    dataset = pd.concat(balanced_frames, ignore_index=True)
    dataset = dataset.sample(frac=1, random_state=42).reset_index(drop=True)

    _dir = os.path.dirname(os.path.abspath(__file__))
    dataset.to_csv(os.path.join(_dir, "data", "synthetic_sensor_data.csv"), index=False)

    print(f"Generated {len(dataset):,} balanced rows across "
          f"{dataset['commodity_type'].nunique()} commodities, "
          f"{dataset['scenario'].nunique()} scenarios.")
    print("\nClass distribution:")
    print(dataset["risk_level"].value_counts().to_string())
    print(dataset["risk_level"].value_counts(normalize=True)
          .mul(100).round(1).to_string())