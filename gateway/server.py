from flask import Flask, request, jsonify
import requests
from datetime import datetime

app = Flask(__name__)

# Cloud Function URL (predict-spoilage with batch + decryption support)
CLOUD_FUNCTION_URL = "https://predict-spoilage-n6hvbwpdfq-el.a.run.app"

# Device → (warehouse, zone) mapping
DEVICE_TO_ZONE = {
    "esp32-node-01": {"warehouse_id": "wh001", "zone_id": "zone-A"},
    "esp32-node-02": {"warehouse_id": "wh001", "zone_id": "zone-B"},
    "esp32-node-03": {"warehouse_id": "wh001", "zone_id": "zone-C"},
    "esp32-node-04": {"warehouse_id": "wh002", "zone_id": "zone-A"},
}

data_count = 0
batch_count = 0


@app.route("/data", methods=["POST"])
def receive_data():
    """Accept encrypted batch or legacy single payloads from ESP32 nodes.

    Encrypted payloads are forwarded AS-IS (gateway never decrypts).
    Legacy payloads are wrapped with zone info and forwarded.
    """
    global data_count, batch_count

    raw = request.get_json(force=True)
    if not raw:
        return jsonify({"error": "No JSON body"}), 400

    device_id = raw.get("device_id", "unknown")
    mapping = DEVICE_TO_ZONE.get(device_id, {})
    warehouse_id = raw.get("warehouse_id") or mapping.get("warehouse_id", "wh001")
    zone_id = raw.get("zone_id") or mapping.get("zone_id", "zone-A")

    is_encrypted = raw.get("encrypted", False)

    # ── Encrypted batch mode (NEW) ────────────────────────────────────
    if is_encrypted:
        # Forward encrypted payload directly — gateway does NOT decrypt
        forward_payload = {
            "warehouse_id": warehouse_id,
            "zone_id": zone_id,
            "commodity_type": raw.get("commodity_type", "tomato"),
            "batch_size": raw.get("batch_size", 10),
            "encrypted": True,
            "iv": raw.get("iv"),
            "ciphertext": raw.get("ciphertext"),
        }

        batch_size = raw.get("batch_size", 10)
        print(f"\n{'='*50}")
        print(f"  🔐 ENCRYPTED BATCH from {device_id}")
        print(f"  📍 {warehouse_id}/{zone_id}")
        print(f"  📦 Expected readings: {batch_size}")
        print(f"  🔑 IV: {raw.get('iv', '?')[:24]}...")
        print(f"  📏 Ciphertext: {len(raw.get('ciphertext', ''))} chars")
        print(f"{'='*50}")

        try:
            resp = requests.post(CLOUD_FUNCTION_URL, json=forward_payload, timeout=30)
            data_count += batch_size
            batch_count += 1
            result = resp.json()
            processed = result.get("processed", 0)
            print(f"  ✅ Cloud: {processed}/{batch_size} processed (HTTP {resp.status_code})")
            return jsonify(result), resp.status_code
        except requests.exceptions.Timeout:
            return jsonify({"error": "Cloud Function timeout on encrypted batch"}), 504
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    # ── Plaintext batch mode ──────────────────────────────────────────
    readings = raw.get("readings")
    if readings and isinstance(readings, list):
        batch_payload = {
            "warehouse_id": warehouse_id,
            "zone_id": zone_id,
            "commodity_type": raw.get("commodity_type", raw.get("commodity", "tomato")),
            "batch": True,
            "readings": readings,
        }

        print(f"\n  📡 PLAINTEXT BATCH from {device_id} | {warehouse_id}/{zone_id}")
        print(f"  Readings: {len(readings)}")

        try:
            resp = requests.post(CLOUD_FUNCTION_URL, json=batch_payload, timeout=30)
            data_count += len(readings)
            batch_count += 1
            return jsonify(resp.json()), resp.status_code
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    # ── Legacy single-reading mode (backward compatible) ──────────────
    commodity = raw.get("commodity_type") or raw.get("commodity", "tomato")
    payload = {
        "warehouse_id": warehouse_id,
        "zone_id": zone_id,
        "commodity_type": commodity,
        "temperature": raw.get("temperature", 0),
        "humidity": raw.get("humidity", 0),
        "co2": raw.get("co2", 400),
        "gas_level": raw.get("gas_level", 0),
        "hours_in_storage": raw.get("hours_in_storage", 0),
    }

    print(f"\n  📡 Single reading from {device_id} → {warehouse_id}/{zone_id}")

    try:
        resp = requests.post(CLOUD_FUNCTION_URL, json=payload, timeout=10)
        data_count += 1
        return jsonify(resp.json()), resp.status_code
    except requests.exceptions.Timeout:
        return jsonify({"error": "Cloud Function timeout"}), 504
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/", methods=["GET"])
def health():
    return jsonify({
        "status": "Gateway running (encrypted batch mode)",
        "cloud_function": CLOUD_FUNCTION_URL,
        "total_readings": data_count,
        "total_batches": batch_count,
        "device_zone_mappings": DEVICE_TO_ZONE,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }), 200


@app.route("/status", methods=["GET"])
def status():
    """Health check with Cloud Function reachability test."""
    try:
        test = {
            "warehouse_id": "wh001",
            "zone_id": "zone-A",
            "commodity_type": "tomato",
            "batch": True,
            "readings": [
                {"temperature": 14.0, "humidity": 90.0, "co2": 400, "gas_level": 20.0}
            ],
        }
        resp = requests.post(CLOUD_FUNCTION_URL, json=test, timeout=10)
        return jsonify({
            "gateway": "running",
            "cloud_function": "reachable",
            "cloud_status": resp.status_code,
            "total_readings": data_count,
            "total_batches": batch_count,
        }), 200
    except Exception as e:
        return jsonify({
            "gateway": "running",
            "cloud_function": "unreachable",
            "error": str(e),
        }), 200


if __name__ == "__main__":
    print("\n" + "=" * 55)
    print("   PostHarvest Gateway (Encrypted Batch + Zone)")
    print("=" * 55)
    print(f"   Cloud Function : {CLOUD_FUNCTION_URL}")
    print(f"   Listening on   : http://0.0.0.0:5000")
    print(f"\n   Device → Zone Mappings:")
    for dev, info in DEVICE_TO_ZONE.items():
        print(f"     {dev}  →  {info['warehouse_id']}/{info['zone_id']}")
    print(f"\n   Modes: encrypted | plaintext-batch | single")
    print("=" * 55 + "\n")
    app.run(host="0.0.0.0", port=5000, debug=True)