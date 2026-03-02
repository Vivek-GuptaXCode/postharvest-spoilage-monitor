from flask import Flask, request, jsonify
import requests
from datetime import datetime

app = Flask(__name__)


CLOUD_FUNCTION_URL = "https://predict-spoilage-n6hvbwpdfq-el.a.run.app"


DEVICE_TO_WAREHOUSE = {
    "esp32-node-01": "wh001",
    "esp32-node-02": "wh002",
    "esp32-node-03": "wh003",
}


data_count = 0


@app.route("/data", methods=["POST"])
def receive_data():
    global data_count

    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "No JSON received"}), 400

        data_count += 1
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    
        device_id    = data.get("device_id", "unknown")
        commodity    = data.get("commodity", "tomato")
        temperature  = data.get("temperature", 0)
        humidity     = data.get("humidity", 0)
        gas_level    = data.get("gas_level", 0)
        co2          = data.get("co2", 400)
        hours        = data.get("hours_in_storage", 0)

        
        if "warehouse_id" in data:
            warehouse_id = data["warehouse_id"]
        else:
            warehouse_id = DEVICE_TO_WAREHOUSE.get(device_id, "wh001")

        print(f"\n{'='*40}")
        print(f"  Data #{data_count} | {timestamp}")
        print(f"{'='*40}")
        print(f"  Device       : {device_id}")
        print(f"  Warehouse ID : {warehouse_id}")
        print(f"  Commodity    : {commodity}")
        print(f"  Temperature  : {temperature}°C")
        print(f"  Humidity     : {humidity}%")
        print(f"  Gas Level    : {gas_level}")
        print(f"  CO2          : {co2}")
        print(f"  Hours Stored : {hours}")

     
        payload = {
            "warehouse_id":     warehouse_id,
            "commodity_type":   commodity,
            "temperature":      temperature,
            "humidity":         humidity,
            "co2":              co2,
            "gas_level":        gas_level,
            "hours_in_storage": hours,
        }

        print(f"\n  >> Sending to Cloud Function...")
        print(f"  >> Payload: {payload}")

        
        resp = requests.post(CLOUD_FUNCTION_URL, json=payload, timeout=10)
        result = resp.json()

       
        risk_level      = result.get("risk_level", "unknown")
        risk_score      = result.get("risk_score", "N/A")
        days_to_spoil   = result.get("days_to_spoilage", "N/A")
        alert           = result.get("alert", "none")

        print(f"\n  << Cloud Response (HTTP {resp.status_code}):")
        print(f"  << Risk Level     : {risk_level}")
        print(f"  << Risk Score     : {risk_score}")
        print(f"  << Days to Spoil  : {days_to_spoil}")
        print(f"  << Alert          : {alert}")
        print(f"{'='*40}\n")

        return jsonify(result), resp.status_code

    except requests.exceptions.Timeout:
        print(f"  !! ERROR: Cloud Function timeout")
        return jsonify({"error": "Cloud Function timeout"}), 504

    except requests.exceptions.ConnectionError:
        print(f"  !! ERROR: Cannot reach Cloud Function")
        return jsonify({"error": "Cannot reach Cloud Function"}), 502

    except Exception as e:
        print(f"  !! ERROR: {e}")
        return jsonify({"error": str(e)}), 500


@app.route("/", methods=["GET"])
def health():
    return jsonify({
        "status": "Flask server running",
        "cloud_function": CLOUD_FUNCTION_URL,
        "total_readings": data_count,
        "device_mappings": DEVICE_TO_WAREHOUSE,
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }), 200


@app.route("/status", methods=["GET"])
def status():
    """Check if Cloud Function is reachable"""
    try:
        test_payload = {
            "warehouse_id":     "wh001",
            "commodity_type":   "tomato",
            "temperature":      14.0,
            "humidity":         90.0,
            "co2":              400,
            "gas_level":        20.0,
            "hours_in_storage": 0
        }
        resp = requests.post(CLOUD_FUNCTION_URL, json=test_payload, timeout=10)
        return jsonify({
            "flask": "running",
            "cloud_function": "reachable",
            "cloud_status": resp.status_code,
            "test_response": resp.json(),
            "total_readings": data_count
        }), 200
    except Exception as e:
        return jsonify({
            "flask": "running",
            "cloud_function": "unreachable",
            "error": str(e),
            "total_readings": data_count
        }), 200


if __name__ == "__main__":
    print("\n" + "=" * 50)
    print("   PostHarvest Flask Gateway")
    print("=" * 50)
    print(f"   Cloud Function : {CLOUD_FUNCTION_URL}")
    print(f"   Listening on   : http://0.0.0.0:5000")
    print(f"\n   Device Mappings:")
    for dev, wh in DEVICE_TO_WAREHOUSE.items():
        print(f"     {dev}  →  {wh}")
    print(f"\n   Endpoints:")
    print(f"     POST /data    - Receive ESP32 data")
    print(f"     GET  /        - Health check")
    print(f"     GET  /status  - Test Cloud Function")
    print(f"\n   Waiting for ESP32 data...")
    print("=" * 50 + "\n")
    app.run(host="0.0.0.0", port=5000, debug=True)