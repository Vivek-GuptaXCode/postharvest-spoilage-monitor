# Scalability Guide — Zone-Aware Batch Ingestion with gRPC + AES-128

> **Workflow:** ESP32 (batch 10 readings) → gRPC + AES-128 encryption → Cloud Function (decrypt + batch predict) → Firestore (zone-aware schema) → Flutter App (zone-aware UI)

---

## Table of Contents

- [Part 1 — Firestore Schema Redesign](#part-1--firestore-schema-redesign)
- [Part 2 — gRPC Service Definition + AES-128 Encryption](#part-2--grpc-service-definition--aes-128-encryption)
- [Part 3 — ESP32 Firmware: Batch + AES-128 Encryption](#part-3--esp32-firmware-batch--aes-128-encryption)
- [Part 4 — Raspberry Pi Gateway: Encrypted Batch Forwarding](#part-4--raspberry-pi-gateway-encrypted-batch-forwarding)
- [Part 5 — Cloud Function: Decrypt, Batch Predict, Zone-Aware Write](#part-5--cloud-function-decrypt-batch-predict-zone-aware-write)
- [Part 6 — Backend REST API: Zone-Aware Endpoints](#part-6--backend-rest-api-zone-aware-endpoints)
- [Part 7 — Flutter App: Zone-Aware Dashboard](#part-7--flutter-app-zone-aware-dashboard)
- [Part 8 — Testing, Simulator, & Demo Scripts](#part-8--testing-simulator--demo-scripts)
- [Implementation Order Summary](#implementation-order-summary)

---

## Part 1 — Firestore Schema Redesign

This must be done **first** as all other layers depend on it.

### Current Schema

```
warehouses/{warehouseId}
  ├── latest/current              ← single real-time doc
  ├── readings/{readingId}        ← flat history
  └── alerts/{alertId}
```

### New Schema

```
warehouses/{warehouseId}
  ├── name, location, commodityType, zoneCount, createdAt
  ├── latest/current              ← warehouse-level AGGREGATE
  ├── readings/{readingId}        ← backward-compat (includes zoneId field)
  ├── alerts/{alertId}            ← now includes zoneId field
  └── zones/
      ├── zone-A/
      │   ├── name, commodityType, createdAt
      │   ├── latest/current      ← zone-specific real-time
      │   └── readings/{readingId}← zone-specific history
      ├── zone-B/
      │   ├── latest/current
      │   └── readings/{readingId}
      └── zone-C/
          ├── latest/current
          └── readings/{readingId}
```

### Step 1: Update `init_firestore.py`

Replace the existing file:

```python
# filepath: scripts/init_firestore.py
from google.cloud import firestore
from datetime import datetime

db = firestore.Client(project="postharvest-hack")

WAREHOUSES = [
    {
        "id": "wh001",
        "name": "Demo Warehouse — Tomato Cold Store",
        "location": firestore.GeoPoint(28.6139, 77.2090),
        "commodityType": "tomato",
        "zones": [
            {"id": "zone-A", "name": "Front Cold Room",   "commodityType": "tomato"},
            {"id": "zone-B", "name": "Mid Storage Bay",   "commodityType": "tomato"},
            {"id": "zone-C", "name": "Loading Dock Area",  "commodityType": "tomato"},
        ],
    },
    {
        "id": "wh002",
        "name": "Demo Warehouse — Potato Store",
        "location": firestore.GeoPoint(26.8467, 80.9462),
        "commodityType": "potato",
        "zones": [
            {"id": "zone-A", "name": "Cold Room 1", "commodityType": "potato"},
            {"id": "zone-B", "name": "Cold Room 2", "commodityType": "potato"},
        ],
    },
]

PLACEHOLDER_LATEST = {
    "temperature": 0.0,
    "humidity": 0.0,
    "co2": 400.0,
    "gasLevel": 0.0,
    "riskScore": 0.0,
    "riskLevel": "low",
    "daysToSpoilage": 14.0,
    "recommendation": "",
    "estimatedLossInr": 0.0,
    "timestamp": datetime.utcnow(),
    "imageUrl": "",
}

for wh in WAREHOUSES:
    ref = db.collection("warehouses").document(wh["id"])
    ref.set({
        "name": wh["name"],
        "location": wh["location"],
        "commodityType": wh["commodityType"],
        "zoneCount": len(wh["zones"]),
        "createdAt": datetime.utcnow(),
    })

    # Warehouse-level aggregate latest
    ref.collection("latest").document("current").set({
        **PLACEHOLDER_LATEST,
        "zoneCount": len(wh["zones"]),
    })

    # Per-zone initialization
    for zone in wh["zones"]:
        zone_ref = ref.collection("zones").document(zone["id"])
        zone_ref.set({
            "name": zone["name"],
            "commodityType": zone["commodityType"],
            "createdAt": datetime.utcnow(),
        })
        zone_ref.collection("latest").document("current").set({
            **PLACEHOLDER_LATEST,
            "zoneId": zone["id"],
            "commodityType": zone["commodityType"],
        })

    print(f"  ✅ {wh['id']}: {len(wh['zones'])} zones initialized")

print(f"\nFirestore initialized: {len(WAREHOUSES)} warehouses with zones.")
```

### Step 2: Update Firestore Indexes

```json
// filepath: backend/m2-backend/firestore.indexes.json
{
  "indexes": [
    {
      "collectionGroup": "readings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "timestamp", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "readings",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "zoneId", "order": "ASCENDING" },
        { "fieldPath": "timestamp", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

### Step 3: Update Firestore Security Rules

```rules
// filepath: backend/m2-backend/firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /warehouses/{warehouseId} {
      allow read: if request.auth != null;

      match /latest/{doc} {
        allow read: if request.auth != null;
      }
      match /readings/{readingId} {
        allow read: if request.auth != null;
      }
      match /alerts/{alertId} {
        allow read: if request.auth != null;
        allow update: if request.auth != null
                      && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['acknowledged']);
      }
      // NEW: zone subcollections
      match /zones/{zoneId} {
        allow read: if request.auth != null;

        match /latest/{doc} {
          allow read: if request.auth != null;
        }
        match /readings/{readingId} {
          allow read: if request.auth != null;
        }
      }
    }
  }
}
```

### Step 4: Update Test Cleanup to Include Zones

In `backend/m2-backend/tests/conftest.py`, update `_cleanup_warehouse`:

```python
def _cleanup_warehouse(client, wh_id):
    """Remove a warehouse and all its subcollections from the emulator."""
    wh_ref = client.collection("warehouses").document(wh_id)
    for sub in ("latest", "readings", "predictions", "alerts"):
        _delete_collection(wh_ref.collection(sub))
    # Clean zone subcollections (NEW)
    for zone_doc in wh_ref.collection("zones").stream():
        for zone_sub in ("latest", "readings"):
            _delete_collection(zone_doc.reference.collection(zone_sub))
        zone_doc.reference.delete()
    wh_ref.delete()
```

### Step 5: Run

```bash
cd scripts
python init_firestore.py
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

---

## Part 2 — gRPC Service Definition + AES-128 Encryption

### Overview

- ESP32 encrypts a batch of 10 sensor readings with **AES-128-CBC**
- Sends encrypted payload via **gRPC** to the Cloud Function
- Cloud Function decrypts, runs ML prediction, writes to Firestore

### Step 1: Create Proto File

```bash
mkdir -p proto
```

```protobuf
// filepath: proto/sensor.proto
syntax = "proto3";

package postharvest;

option java_multiple_files = true;
option java_package = "com.postharvest.grpc";

// ─── Messages ────────────────────────────────────────────────────────

// A single sensor sample (unencrypted, used inside the batch)
message SensorSample {
  float temperature       = 1;
  float humidity          = 2;
  float gas_level         = 3;
  float co2               = 4;
  uint32 sample_offset_ms = 5;   // millis() at capture time
}

// Encrypted batch payload sent from ESP32 → Cloud
message EncryptedBatchRequest {
  string device_id      = 1;
  string warehouse_id   = 2;
  string zone_id        = 3;
  string commodity_type = 4;
  bytes  iv             = 5;     // 16-byte AES-128-CBC IV
  bytes  ciphertext     = 6;     // AES-128-CBC encrypted SensorBatch
  uint32 batch_size     = 7;     // expected number of samples
}

// The plaintext batch (serialized, then encrypted)
message SensorBatch {
  repeated SensorSample readings = 1;
}

// Single prediction result
message PredictionResult {
  string zone_id          = 1;
  string risk_level       = 2;
  float  risk_score       = 3;
  float  days_to_spoilage = 4;
  string recommendation   = 5;
  float  estimated_loss   = 6;
  int32  index            = 7;
}

// Cloud Function response
message BatchPredictionResponse {
  string status       = 1;
  string warehouse_id = 2;
  string zone_id      = 3;
  uint32 batch_size   = 4;
  uint32 processed    = 5;
  string timestamp    = 6;
  repeated PredictionResult results = 7;
}

// ─── Service ─────────────────────────────────────────────────────────

service SpoilagePrediction {
  // ESP32 sends encrypted batch → Cloud decrypts, predicts, stores
  rpc PredictBatch (EncryptedBatchRequest) returns (BatchPredictionResponse);
}
```

### Step 2: Generate Python gRPC Stubs (for Cloud Function)

```bash
pip install grpcio grpcio-tools protobuf

python -m grpc_tools.protoc \
  -I proto/ \
  --python_out=cloud-functions/predict/generated/ \
  --grpc_python_out=cloud-functions/predict/generated/ \
  proto/sensor.proto
```

Create the output directory first:

```bash
mkdir -p cloud-functions/predict/generated
touch cloud-functions/predict/generated/__init__.py
```

### Step 3: Shared AES-128 Key Management

#### Pre-shared Key (PSK) approach for hackathon

Both ESP32 and Cloud Function use the same hardcoded 16-byte key. In production, use KMS or Vault.

```python
# filepath: cloud-functions/predict/crypto_config.py
"""
AES-128-CBC Pre-Shared Key for sensor data encryption.

HACKATHON NOTE: In production, retrieve from Google Cloud Secret Manager:
    from google.cloud import secretmanager
    client = secretmanager.SecretManagerServiceClient()
    key = client.access_secret_version(
        name="projects/postharvest-hack/secrets/aes-key/versions/latest"
    )

For the hackathon, we use a hardcoded PSK that matches the ESP32 firmware.
"""

import os

# 16 bytes = AES-128. Must match ESP32 firmware exactly.
AES_128_KEY = os.environ.get(
    "AES_128_KEY",
    b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10"
)

# If env var is a hex string, convert it
if isinstance(AES_128_KEY, str):
    AES_128_KEY = bytes.fromhex(AES_128_KEY)

assert len(AES_128_KEY) == 16, f"AES key must be 16 bytes, got {len(AES_128_KEY)}"
```

### Step 4: Decryption Utility

```python
# filepath: cloud-functions/predict/aes_decrypt.py
"""
AES-128-CBC decryption for incoming ESP32 sensor batches.

The ESP32 encrypts a protobuf-serialized SensorBatch using AES-128-CBC
with PKCS7 padding. This module decrypts it.
"""

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.backends import default_backend


def decrypt_aes128_cbc(key: bytes, iv: bytes, ciphertext: bytes) -> bytes:
    """Decrypt AES-128-CBC with PKCS7 padding.

    Args:
        key:        16-byte AES key
        iv:         16-byte initialization vector
        ciphertext: encrypted data (multiple of 16 bytes)

    Returns:
        Decrypted plaintext bytes

    Raises:
        ValueError: if key/iv length is wrong or padding is invalid
    """
    if len(key) != 16:
        raise ValueError(f"AES-128 key must be 16 bytes, got {len(key)}")
    if len(iv) != 16:
        raise ValueError(f"IV must be 16 bytes, got {len(iv)}")
    if len(ciphertext) == 0 or len(ciphertext) % 16 != 0:
        raise ValueError(f"Ciphertext length must be multiple of 16, got {len(ciphertext)}")

    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    decryptor = cipher.decryptor()
    padded_plaintext = decryptor.update(ciphertext) + decryptor.finalize()

    # Remove PKCS7 padding
    unpadder = padding.PKCS7(128).unpadder()
    plaintext = unpadder.update(padded_plaintext) + unpadder.finalize()

    return plaintext
```

### Step 5: Add Dependencies

```txt
# filepath: cloud-functions/predict/requirements.txt
functions-framework==3.*
firebase-admin>=6.0
google-cloud-firestore>=2.16
google-cloud-bigquery>=3.10
numpy>=1.24
xgboost>=2.0
scikit-learn>=1.3
grpcio>=1.60.0
protobuf>=4.25.0
cryptography>=41.0.0
```

### Traffic Reduction Analysis

| Metric | Before (HTTP, single) | After (gRPC, batch+encrypted) |
|--------|----------------------|-------------------------------|
| Requests per ESP32 per 100s | 10 | 1 |
| Payload encoding | JSON (~200 bytes each) | Protobuf (~60 bytes each, 10 packed ~600 bytes) |
| Encrypted overhead | None | +16 IV + PKCS7 padding (~32 bytes) |
| TLS handshakes | 10 | 1 |
| Total bytes per 100s | ~2000+ headers | ~700 encrypted + single header |
| **Overall reduction** | — | **~80-85% less traffic** |

---

## Part 3 — ESP32 Firmware: Batch + AES-128 Encryption

### Overview

Each ESP32 node:

1. Samples sensors every 10 seconds
2. Buffers 10 readings in memory
3. Serializes as protobuf `SensorBatch`
4. Encrypts with AES-128-CBC + random IV
5. Wraps in `EncryptedBatchRequest` protobuf
6. POSTs to gateway (or directly to Cloud Function)

### Step 1: Install Required Libraries

In Arduino IDE, install:

- **Nanopb** (lightweight protobuf for embedded) — available via Library Manager
- AES is built-in to ESP32 via `mbedtls`

### Step 2: Generate Nanopb Stubs

```bash
# Install nanopb
pip install nanopb

# Generate C stubs from proto
cd proto
nanopb_generator sensor.proto
# Produces: sensor.pb.h, sensor.pb.c
```

Copy `sensor.pb.h` and `sensor.pb.c` into `firmware/esp32_sensor/`.

### Step 3: Create Nanopb Options File

```
// filepath: firmware/esp32_sensor/sensor.options
postharvest.SensorBatch.readings  max_count:10
```

### Step 4: Replace Firmware

```cpp
// filepath: firmware/esp32_sensor/esp32_sensor.ino
#include <WiFi.h>
#include <HTTPClient.h>
#include "mbedtls/aes.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/base64.h"
#include <pb_encode.h>
#include "sensor.pb.h"

// ── WiFi Configuration ──────────────────────────────────────────────
const char* WIFI_SSID     = "......";
const char* WIFI_PASSWORD = "........";

// ── Gateway / Cloud Endpoint ────────────────────────────────────────
const char* SERVER_IP   = "10.43.65.24";
const int   SERVER_PORT = 5000;

// ── Identity ────────────────────────────────────────────────────────
const char* DEVICE_ID     = "esp32-node-01";
const char* WAREHOUSE_ID  = "wh001";
const char* ZONE_ID       = "zone-A";

// ── AES-128 Pre-Shared Key (MUST match Cloud Function) ──────────────
static const uint8_t AES_KEY[16] = {
  0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10
};

// ── Batch Configuration ─────────────────────────────────────────────
#define SAMPLE_INTERVAL   10000   // 10 seconds between samples
#define BATCH_SIZE        10      // 10 readings per encrypted batch

unsigned long lastSample = 0;
int batchIndex = 0;

// ── Sensor Buffer ───────────────────────────────────────────────────
struct SensorSample {
  float temperature;
  float humidity;
  float gasLevel;
  float co2;
  unsigned long timestampMs;
};

SensorSample batch[BATCH_SIZE];

int selectedCommodity = 0;

struct Commodity {
  const char* name;
  float temp_min, temp_max, rh_min, rh_max;
};

Commodity commodities[] = {
  { "tomato",  12.0, 15.0, 85.0, 95.0 },
  { "potato",   4.0,  5.0, 95.0, 98.0 },
  { "banana",  13.0, 14.0, 90.0, 95.0 },
  { "rice",    15.0, 20.0, 50.0, 65.0 },
  { "onion",    0.0,  2.0, 65.0, 70.0 }
};

// ── RNG for IV generation ───────────────────────────────────────────
mbedtls_entropy_context entropy;
mbedtls_ctr_drbg_context ctr_drbg;

float randomFloat(float minVal, float maxVal) {
  return minVal + (float)random(0, 10000) / 10000.0 * (maxVal - minVal);
}

// ── PKCS7 Padding ───────────────────────────────────────────────────
int pkcs7_pad(uint8_t* data, int data_len, int block_size) {
  int pad_len = block_size - (data_len % block_size);
  for (int i = 0; i < pad_len; i++) {
    data[data_len + i] = (uint8_t)pad_len;
  }
  return data_len + pad_len;
}

// ── AES-128-CBC Encrypt ─────────────────────────────────────────────
bool aes128_cbc_encrypt(const uint8_t* key, const uint8_t* iv,
                         const uint8_t* plaintext, int plain_len,
                         uint8_t* ciphertext, int* cipher_len) {
  // PKCS7 pad into a temp buffer
  int padded_len = plain_len + (16 - (plain_len % 16));
  uint8_t* padded = (uint8_t*)malloc(padded_len);
  if (!padded) return false;

  memcpy(padded, plaintext, plain_len);
  padded_len = pkcs7_pad(padded, plain_len, 16);

  // AES-CBC encrypt
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, key, 128);

  // CBC needs a mutable IV copy
  uint8_t iv_copy[16];
  memcpy(iv_copy, iv, 16);

  int ret = mbedtls_aes_crypt_cbc(&aes, MBEDTLS_AES_ENCRYPT,
                                   padded_len, iv_copy, padded, ciphertext);
  mbedtls_aes_free(&aes);
  free(padded);

  if (ret != 0) return false;
  *cipher_len = padded_len;
  return true;
}

void setup() {
  Serial.begin(115200);
  Serial.println("\n================================");
  Serial.println("PostHarvest - gRPC + AES-128 Batch Mode");
  Serial.printf("Zone: %s | Batch: %d readings\n", ZONE_ID, BATCH_SIZE);
  Serial.println("================================");

  randomSeed(analogRead(0) + millis());

  // Initialize mbedtls RNG for IV generation
  mbedtls_entropy_init(&entropy);
  mbedtls_ctr_drbg_init(&ctr_drbg);
  mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                          (const uint8_t*)"postharvest", 11);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected: " + WiFi.localIP().toString());
}

void loop() {
  if (millis() - lastSample >= SAMPLE_INTERVAL) {
    lastSample = millis();
    sampleSensor();
  }
}

void sampleSensor() {
  Commodity c = commodities[selectedCommodity];

  batch[batchIndex].temperature = randomFloat(c.temp_min, c.temp_max);
  batch[batchIndex].humidity    = randomFloat(c.rh_min, c.rh_max);
  batch[batchIndex].gasLevel    = randomFloat(5.0, 40.0);
  batch[batchIndex].co2         = randomFloat(380.0, 500.0);
  batch[batchIndex].timestampMs = millis();

  // 20% chance abnormal (same logic as original)
  if (random(0, 100) < 20) {
    int alertType = random(0, 3);
    switch (alertType) {
      case 0: batch[batchIndex].temperature = randomFloat(c.temp_max + 3, c.temp_max + 12); break;
      case 1: batch[batchIndex].humidity = randomFloat(c.rh_min - 30, c.rh_min - 5); break;
      case 2: batch[batchIndex].gasLevel = randomFloat(55.0, 90.0); break;
    }
  }

  Serial.printf("[Sample %d/%d] T:%.1f H:%.1f G:%.1f CO2:%.0f\n",
    batchIndex + 1, BATCH_SIZE,
    batch[batchIndex].temperature, batch[batchIndex].humidity,
    batch[batchIndex].gasLevel, batch[batchIndex].co2);

  batchIndex++;
  if (batchIndex >= BATCH_SIZE) {
    sendEncryptedBatch();
    batchIndex = 0;
  }
}

void sendEncryptedBatch() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost! Reconnecting...");
    WiFi.reconnect();
    delay(3000);
    return;
  }

  // ── 1. Serialize SensorBatch via nanopb ────────────────────────────
  uint8_t pb_buffer[1024];
  pb_ostream_t stream = pb_ostream_from_buffer(pb_buffer, sizeof(pb_buffer));

  postharvest_SensorBatch sensor_batch = postharvest_SensorBatch_init_zero;
  sensor_batch.readings_count = BATCH_SIZE;

  for (int i = 0; i < BATCH_SIZE; i++) {
    sensor_batch.readings[i].temperature      = batch[i].temperature;
    sensor_batch.readings[i].humidity          = batch[i].humidity;
    sensor_batch.readings[i].gas_level         = batch[i].gasLevel;
    sensor_batch.readings[i].co2               = batch[i].co2;
    sensor_batch.readings[i].sample_offset_ms  = (uint32_t)batch[i].timestampMs;
  }

  if (!pb_encode(&stream, postharvest_SensorBatch_fields, &sensor_batch)) {
    Serial.printf("Protobuf encode failed: %s\n", PB_GET_ERROR(&stream));
    return;
  }
  int pb_len = stream.bytes_written;
  Serial.printf("Protobuf serialized: %d bytes\n", pb_len);

  // ── 2. Generate random 16-byte IV ─────────────────────────────────
  uint8_t iv[16];
  mbedtls_ctr_drbg_random(&ctr_drbg, iv, 16);

  // ── 3. AES-128-CBC encrypt ────────────────────────────────────────
  int cipher_max = pb_len + 16; // PKCS7 can add up to 16 bytes
  uint8_t* ciphertext = (uint8_t*)malloc(cipher_max);
  int cipher_len = 0;

  if (!aes128_cbc_encrypt(AES_KEY, iv, pb_buffer, pb_len, ciphertext, &cipher_len)) {
    Serial.println("AES encryption failed!");
    free(ciphertext);
    return;
  }
  Serial.printf("Encrypted: %d bytes (from %d plaintext)\n", cipher_len, pb_len);

  // ── 4. Encode IV + ciphertext as base64 for HTTP transport ────────
  size_t iv_b64_len = 0, ct_b64_len = 0;
  char iv_b64[32], ct_b64[2048];

  mbedtls_base64_encode((uint8_t*)iv_b64, sizeof(iv_b64), &iv_b64_len, iv, 16);
  iv_b64[iv_b64_len] = '\0';

  mbedtls_base64_encode((uint8_t*)ct_b64, sizeof(ct_b64), &ct_b64_len,
                         ciphertext, cipher_len);
  ct_b64[ct_b64_len] = '\0';

  free(ciphertext);

  // ── 5. Build JSON wrapper and POST ────────────────────────────────
  String json = "{";
  json += "\"device_id\":\"" + String(DEVICE_ID) + "\",";
  json += "\"warehouse_id\":\"" + String(WAREHOUSE_ID) + "\",";
  json += "\"zone_id\":\"" + String(ZONE_ID) + "\",";
  json += "\"commodity_type\":\"" + String(commodities[selectedCommodity].name) + "\",";
  json += "\"batch_size\":" + String(BATCH_SIZE) + ",";
  json += "\"encrypted\":true,";
  json += "\"iv\":\"" + String(iv_b64) + "\",";
  json += "\"ciphertext\":\"" + String(ct_b64) + "\"";
  json += "}";

  String url = "http://" + String(SERVER_IP) + ":" + String(SERVER_PORT) + "/data";
  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(15000);

  Serial.printf(">> Sending encrypted batch (%d bytes payload)...\n", json.length());
  int httpCode = http.POST(json);

  if (httpCode == 200) {
    Serial.println("✅ Batch accepted");
    Serial.println(http.getString());
  } else {
    Serial.printf("❌ HTTP %d\n", httpCode);
  }
  http.end();
}
```

### Key Points

1. **10x traffic reduction**: One POST every ~100s instead of 10
2. **AES-128-CBC encryption**: Random IV per batch, PKCS7 padding
3. **Protobuf serialization**: ~60% smaller than JSON per reading
4. **Zone assignment**: Each ESP32 has a hardcoded `ZONE_ID`
5. **Pre-shared key**: Same 16-byte key on ESP32 and Cloud Function

---

## Part 4 — Raspberry Pi Gateway: Encrypted Batch Forwarding

### Overview

The gateway receives encrypted batch payloads from ESP32 nodes and forwards them to the Cloud Function **without decrypting** (zero-knowledge relay).

### Step 1: Replace `gateway/server.py`

```python
# filepath: gateway/server.py
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
```

### Key Points

- Gateway is a **zero-knowledge relay** — never touches unencrypted sensor data
- Supports 3 modes: encrypted batch, plaintext batch, legacy single
- Adds `zone_id` from device mapping if ESP32 doesn't include it
- 30s timeout for batch (vs 10s for single) — ML inference takes longer

---

## Part 5 — Cloud Function: Decrypt, Batch Predict, Zone-Aware Write

### Overview

The `predict-spoilage` Cloud Function is updated to:

1. Detect encrypted vs plaintext payloads
2. Decrypt AES-128-CBC ciphertext
3. Deserialize protobuf `SensorBatch`
4. Run ML inference on each reading in the batch
5. Write per-zone + warehouse-level data to Firestore
6. Batch-insert to BigQuery (single API call)

### Step 1: New File Structure

```
cloud-functions/predict/
├── main.py                     ← MODIFIED (batch + decrypt)
├── aes_decrypt.py              ← NEW
├── crypto_config.py            ← NEW
├── generated/
│   ├── __init__.py
│   ├── sensor_pb2.py           ← generated from proto
│   └── sensor_pb2_grpc.py      ← generated from proto
├── requirements.txt            ← MODIFIED
├── risk_score_model.pkl
├── spoilage_regressor.pkl
├── model_metadata.pkl
└── commodity_thresholds.json
```

### Step 2: Update `main.py`

```python
# filepath: cloud-functions/predict/main.py
import json
import os
import pickle
import base64
from datetime import datetime

import firebase_admin
import functions_framework
import numpy as np
from firebase_admin import messaging
from google.cloud import bigquery, firestore

from aes_decrypt import decrypt_aes128_cbc
from crypto_config import AES_128_KEY

# ═══════════════════════════════════════════════════════════════════════
# GLOBAL SCOPE — loaded ONCE on cold start
# ═══════════════════════════════════════════════════════════════════════

_DIR = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(_DIR, "risk_score_model.pkl"), "rb") as f:
    RISK_MODEL = pickle.load(f)

with open(os.path.join(_DIR, "spoilage_regressor.pkl"), "rb") as f:
    REGRESSOR = pickle.load(f)

with open(os.path.join(_DIR, "model_metadata.pkl"), "rb") as f:
    METADATA = pickle.load(f)

with open(os.path.join(_DIR, "commodity_thresholds.json"), "r") as f:
    THRESHOLDS = json.load(f)

if not firebase_admin._apps:
    firebase_admin.initialize_app()

db = firestore.Client()
bq = bigquery.Client()

PROJECT_ID = os.environ.get("GCP_PROJECT", "postharvest-hack")
BQ_TABLE = f"{PROJECT_ID}.postharvest.sensor_readings"

# Try to import generated protobuf (optional — falls back to JSON)
try:
    from generated import sensor_pb2
    PROTOBUF_AVAILABLE = True
    print("[Init] Protobuf stubs loaded successfully")
except ImportError:
    PROTOBUF_AVAILABLE = False
    print("[Init] Protobuf stubs not found — encrypted mode will use JSON fallback")


# ═══════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════

def _build_feature_vector(data: dict) -> np.ndarray:
    """Map incoming sensor JSON to the feature vector expected by the model."""
    temp = data.get("temperature", 25)
    hum  = data.get("humidity", 60)
    commodity = data.get("commodity_type", "tomato")

    COMMODITY_MAP = {"tomato": 0, "potato": 1, "banana": 2, "rice": 3, "onion": 4}
    commodity_encoded = COMMODITY_MAP.get(commodity, 0)

    svp = 0.6108 * np.exp(17.27 * temp / (temp + 237.3))
    avp = svp * (hum / 100.0)
    vpd = svp - avp

    OPTIMAL_TEMP_MID = {
        "tomato": 13.5, "potato": 4.5, "banana": 13.5,
        "rice": 17.5, "onion": 1.0,
    }
    OPTIMAL_RH_MID = {
        "tomato": 90.0, "potato": 96.5, "banana": 92.5,
        "rice": 57.5, "onion": 67.5,
    }
    temp_deviation = abs(temp - OPTIMAL_TEMP_MID.get(commodity, 13.5))
    humidity_deviation = abs(hum - OPTIMAL_RH_MID.get(commodity, 90.0))
    hours = data.get("hours_in_storage", 0)
    temp_hours_stress = temp_deviation * hours

    return np.array([[
        temp, hum,
        data.get("co2", 400),
        data.get("gas_level", 0),
        hours, commodity_encoded, vpd,
        temp_deviation, humidity_deviation, temp_hours_stress,
    ]])


def _generate_recommendation(data: dict, risk_level: str) -> str:
    """Return an actionable recommendation based on dominant risk factor."""
    temp = data.get("temperature", 25)
    hum  = data.get("humidity", 60)
    gas  = data.get("gas_level", 0)

    if risk_level in ("low",):
        return "Conditions are within safe range. Continue monitoring."

    issues = []
    commodity = data.get("commodity_type", "tomato")
    thresholds = THRESHOLDS.get(commodity, {})

    if temp > thresholds.get("temp_max", 30):
        issues.append(f"Reduce temperature below {thresholds.get('temp_max', 30)}°C immediately.")
    if hum < thresholds.get("rh_min", 60):
        issues.append(f"Increase humidity above {thresholds.get('rh_min', 60)}%.")
    if gas > 50:
        issues.append("High gas/VOC levels detected — check for ethylene-producing items.")

    if not issues:
        issues.append("Monitor closely — conditions are borderline.")

    return " ".join(issues)


def _estimate_loss_inr(commodity: str, days_to_spoilage: float,
                        quantity_kg: float = 1000) -> float:
    """Approximate monetary loss if current conditions persist."""
    PRICES = {"tomato": 40, "potato": 25, "banana": 35, "rice": 45, "onion": 30}
    price = PRICES.get(commodity, 35)
    if days_to_spoilage >= 7:
        return 0.0
    loss_fraction = max(0, (7 - days_to_spoilage) / 7)
    return round(loss_fraction * quantity_kg * price, 2)


# ═══════════════════════════════════════════════════════════════════════
# DECRYPTION (NEW)
# ═══════════════════════════════════════════════════════════════════════

def _decrypt_batch(data: dict) -> list[dict]:
    """Decrypt AES-128-CBC encrypted protobuf payload.

    Input: {"iv": "<base64>", "ciphertext": "<base64>"}
    Output: list of dict readings
    """
    iv_b64 = data.get("iv", "")
    ct_b64 = data.get("ciphertext", "")

    if not iv_b64 or not ct_b64:
        raise ValueError("Missing 'iv' or 'ciphertext' in encrypted payload")

    iv = base64.b64decode(iv_b64)
    ciphertext = base64.b64decode(ct_b64)

    print(f"[Decrypt] IV: {len(iv)} bytes, Ciphertext: {len(ciphertext)} bytes")

    plaintext = decrypt_aes128_cbc(AES_128_KEY, iv, ciphertext)

    print(f"[Decrypt] Decrypted: {len(plaintext)} bytes")

    # Deserialize protobuf if available
    if PROTOBUF_AVAILABLE:
        batch = sensor_pb2.SensorBatch()
        batch.ParseFromString(plaintext)
        readings = []
        for sample in batch.readings:
            readings.append({
                "temperature": round(float(sample.temperature), 1),
                "humidity": round(float(sample.humidity), 1),
                "gas_level": round(float(sample.gas_level), 1),
                "co2": round(float(sample.co2), 1),
                "sample_offset_ms": int(sample.sample_offset_ms),
            })
        return readings
    else:
        # Fallback: treat decrypted plaintext as JSON
        import json as _json
        return _json.loads(plaintext.decode("utf-8"))


# ═══════════════════════════════════════════════════════════════════════
# SINGLE READING PROCESSOR
# ═══════════════════════════════════════════════════════════════════════

def _process_single_reading(data: dict, warehouse_id: str, zone_id: str,
                             commodity: str, timestamp) -> dict:
    """Process one reading: ML inference + Firestore writes for a zone."""
    features = _build_feature_vector(data)

    risk_score_raw = float(RISK_MODEL.predict(features)[0])
    risk_score = round(max(0.0, min(100.0, risk_score_raw)), 2)

    if risk_score <= 25:    risk_level = "low"
    elif risk_score <= 50:  risk_level = "medium"
    elif risk_score <= 75:  risk_level = "high"
    else:                   risk_level = "critical"

    days_to_spoilage = round(float(REGRESSOR.predict(features)[0]), 2)
    days_to_spoilage = max(days_to_spoilage, 0)

    recommendation = _generate_recommendation(data, risk_level)
    estimated_loss = _estimate_loss_inr(commodity, days_to_spoilage)

    wh_ref = db.collection("warehouses").document(warehouse_id)

    reading = {
        "temperature":      data["temperature"],
        "humidity":         data["humidity"],
        "co2":              data.get("co2", 400),
        "gasLevel":         data.get("gas_level", 0),
        "riskScore":        risk_score,
        "riskLevel":        risk_level,
        "daysToSpoilage":   days_to_spoilage,
        "recommendation":   recommendation,
        "estimatedLossInr": estimated_loss,
        "commodityType":    commodity,
        "zoneId":           zone_id,
        "timestamp":        timestamp,
        "imageUrl":         data.get("image_url", ""),
    }

    # ── Per-zone latest (NEW) ─────────────────────────────────────────
    zone_ref = wh_ref.collection("zones").document(zone_id)
    zone_ref.set({"name": zone_id, "commodityType": commodity}, merge=True)
    zone_ref.collection("latest").document("current").set(reading, merge=True)

    # ── Per-zone readings history (NEW) ───────────────────────────────
    zone_ref.collection("readings").add({**reading, "timestamp": timestamp})

    # ── Backward-compatible warehouse-level readings ──────────────────
    wh_ref.collection("readings").add({**reading, "timestamp": timestamp})

    # ── Alerts on high/critical ───────────────────────────────────────
    if risk_level in ("high", "critical"):
        alert_doc = {
            "type":         f"{risk_level}_risk",
            "severity":     "critical" if risk_level == "critical" else "warning",
            "zoneId":       zone_id,
            "message": (
                f"[{zone_id}] Spoilage risk is {risk_level.upper()}! "
                f"Temp {data['temperature']}°C · Humidity {data['humidity']}% · "
                f"Est. shelf life {days_to_spoilage} days. {recommendation}"
            ),
            "timestamp":    timestamp,
            "acknowledged": False,
        }
        wh_ref.collection("alerts").add(alert_doc)

        try:
            fcm_msg = messaging.Message(
                notification=messaging.Notification(
                    title=f"⚠️ {risk_level.upper()} — {commodity.title()} [{zone_id}]",
                    body=alert_doc["message"],
                ),
                data={
                    "warehouse_id": warehouse_id,
                    "zone_id":      zone_id,
                    "risk_level":   risk_level,
                    "risk_score":   str(risk_score),
                },
                topic=f"warehouse_{warehouse_id}",
            )
            messaging.send(fcm_msg)
        except Exception as e:
            print(f"[FCM error] {e}")

    return {
        "zone_id":            zone_id,
        "risk_level":         risk_level,
        "risk_score":         risk_score,
        "days_to_spoilage":   days_to_spoilage,
        "recommendation":     recommendation,
        "estimated_loss_inr": estimated_loss,
    }


def _update_warehouse_aggregate(warehouse_id: str, zone_results: list[dict]):
    """Compute warehouse-level aggregate from zone results."""
    if not zone_results:
        return

    wh_ref = db.collection("warehouses").document(warehouse_id)

    avg_risk   = sum(r["risk_score"] for r in zone_results) / len(zone_results)
    max_risk   = max(r["risk_score"] for r in zone_results)
    min_days   = min(r["days_to_spoilage"] for r in zone_results)
    total_loss = sum(r["estimated_loss_inr"] for r in zone_results)

    if max_risk <= 25:      agg_level = "low"
    elif max_risk <= 50:    agg_level = "medium"
    elif max_risk <= 75:    agg_level = "high"
    else:                   agg_level = "critical"

    wh_ref.collection("latest").document("current").set({
        "riskScore":        round(avg_risk, 2),
        "riskLevel":        agg_level,
        "maxRiskScore":     round(max_risk, 2),
        "daysToSpoilage":   round(min_days, 2),
        "estimatedLossInr": round(total_loss, 2),
        "zoneCount":        len(zone_results),
        "timestamp":        datetime.utcnow(),
    }, merge=True)


# ═══════════════════════════════════════════════════════════════════════
# HTTP HANDLER (MODIFIED)
# ═══════════════════════════════════════════════════════════════════════

@functions_framework.http
def predict_handler(request):
    """Accepts POST with encrypted batch, plaintext batch, or single reading."""

    # ── CORS ──────────────────────────────────────────────────────────
    if request.method == "OPTIONS":
        return ("", 204, {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST",
            "Access-Control-Allow-Headers": "Content-Type",
            "Access-Control-Max-Age": "3600",
        })

    headers = {"Access-Control-Allow-Origin": "*"}
    data = request.get_json(silent=True)
    if not data:
        return ({"error": "Invalid JSON payload."}, 400, headers)

    warehouse_id = data.get("warehouse_id", "wh001")
    zone_id      = data.get("zone_id", "zone-A")
    commodity    = data.get("commodity_type", "tomato")
    is_encrypted = data.get("encrypted", False)
    is_batch     = data.get("batch", False)
    timestamp    = datetime.utcnow()

    # ══════════════════════════════════════════════════════════════
    # MODE 1: Encrypted batch (gRPC-style)
    # ══════════════════════════════════════════════════════════════
    if is_encrypted:
        try:
            readings_list = _decrypt_batch(data)
            print(f"[Encrypted] Decrypted {len(readings_list)} readings "
                  f"for {warehouse_id}/{zone_id}")
        except Exception as e:
            print(f"[Decrypt ERROR] {e}")
            return ({"error": f"Decryption failed: {str(e)}"}, 400, headers)

        if not readings_list:
            return ({"error": "Decrypted batch is empty"}, 400, headers)

        results = []
        bq_rows = []

        for i, reading in enumerate(readings_list):
            reading.setdefault("commodity_type", commodity)
            reading.setdefault("hours_in_storage", data.get("hours_in_storage", 0))

            if "temperature" not in reading or "humidity" not in reading:
                results.append({"index": i, "error": "Missing temperature or humidity"})
                continue

            result = _process_single_reading(
                reading, warehouse_id, zone_id, commodity, timestamp
            )
            result["index"] = i
            results.append(result)

            bq_rows.append({
                "warehouse_id":     warehouse_id,
                "zone_id":          zone_id,
                "temperature":      reading["temperature"],
                "humidity":         reading["humidity"],
                "co2":              reading.get("co2", 400),
                "gas_level":        reading.get("gas_level", 0),
                "risk_score":       result["risk_score"],
                "risk_level":       result["risk_level"],
                "commodity_type":   commodity,
                "days_to_spoilage": result["days_to_spoilage"],
                "timestamp":        timestamp.isoformat(),
            })

        if bq_rows:
            try:
                bq.insert_rows_json(BQ_TABLE, bq_rows)
            except Exception as e:
                print(f"[BigQuery batch insert error] {e}")

        successful = [r for r in results if "error" not in r]
        _update_warehouse_aggregate(warehouse_id, successful)

        return ({
            "status":       "ok",
            "encrypted":    True,
            "batch_size":   len(readings_list),
            "processed":    len(successful),
            "zone_id":      zone_id,
            "warehouse_id": warehouse_id,
            "results":      results,
            "timestamp":    timestamp.isoformat(),
        }, 200, headers)

    # ══════════════════════════════════════════════════════════════
    # MODE 2: Plaintext batch
    # ══════════════════════════════════════════════════════════════
    if is_batch and "readings" in data:
        readings_list = data["readings"]
        if not isinstance(readings_list, list) or len(readings_list) == 0:
            return ({"error": "Batch 'readings' must be a non-empty array."}, 400, headers)
        if len(readings_list) > 50:
            return ({"error": "Batch size exceeds maximum of 50."}, 400, headers)

        results = []
        bq_rows = []

        for i, reading in enumerate(readings_list):
            reading.setdefault("commodity_type", commodity)
            reading.setdefault("hours_in_storage", data.get("hours_in_storage", 0))

            if "temperature" not in reading or "humidity" not in reading:
                results.append({"index": i, "error": "Missing temperature or humidity"})
                continue

            result = _process_single_reading(
                reading, warehouse_id, zone_id, commodity, timestamp
            )
            result["index"] = i
            results.append(result)

            bq_rows.append({
                "warehouse_id": warehouse_id, "zone_id": zone_id,
                "temperature": reading["temperature"],
                "humidity": reading["humidity"],
                "co2": reading.get("co2", 400),
                "gas_level": reading.get("gas_level", 0),
                "risk_score": result["risk_score"],
                "risk_level": result["risk_level"],
                "commodity_type": commodity,
                "days_to_spoilage": result["days_to_spoilage"],
                "timestamp": timestamp.isoformat(),
            })

        if bq_rows:
            try:
                bq.insert_rows_json(BQ_TABLE, bq_rows)
            except Exception as e:
                print(f"[BigQuery batch error] {e}")

        successful = [r for r in results if "error" not in r]
        _update_warehouse_aggregate(warehouse_id, successful)

        return ({
            "status": "ok", "batch_size": len(readings_list),
            "processed": len(successful), "zone_id": zone_id,
            "warehouse_id": warehouse_id, "results": results,
            "timestamp": timestamp.isoformat(),
        }, 200, headers)

    # ══════════════════════════════════════════════════════════════
    # MODE 3: Single reading (backward compatible)
    # ══════════════════════════════════════════════════════════════
    if "temperature" not in data or "humidity" not in data:
        return ({"error": "Required: temperature, humidity."}, 400, headers)

    result = _process_single_reading(data, warehouse_id, zone_id, commodity, timestamp)
    _update_warehouse_aggregate(warehouse_id, [result])

    try:
        bq.insert_rows_json(BQ_TABLE, [{
            "warehouse_id": warehouse_id, "zone_id": zone_id,
            "temperature": data["temperature"], "humidity": data["humidity"],
            "co2": data.get("co2", 400), "gas_level": data.get("gas_level", 0),
            "risk_score": result["risk_score"], "risk_level": result["risk_level"],
            "commodity_type": commodity,
            "days_to_spoilage": result["days_to_spoilage"],
            "timestamp": timestamp.isoformat(),
        }])
    except Exception as e:
        print(f"[BigQuery error] {e}")

    return ({
        "status": "ok", "zone_id": zone_id, **result,
        "timestamp": timestamp.isoformat(),
    }, 200, headers)
```

### Step 3: Deploy

```bash
cd cloud-functions/predict

# Set AES key as env var (or hardcode for hackathon)
gcloud functions deploy predict-spoilage \
  --gen2 \
  --runtime=python312 \
  --region=asia-south1 \
  --entry-point=predict_handler \
  --trigger-http \
  --allow-unauthenticated \
  --memory=512MiB \
  --timeout=120s \
  --set-env-vars="AES_128_KEY=0102030405060708090a0b0c0d0e0f10"
```

---

## Part 6 — Backend REST API: Zone-Aware Endpoints

### New Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/warehouse/{id}/zones` | List all zones with latest status |
| GET | `/warehouse/{id}/zone/{zoneId}/summary` | Zone-level 24h stats |

### Step 1: Add Zone Endpoints to `api-function/main.py`

```python
# filepath: backend/m2-backend/api-function/main.py
# Add these functions BEFORE the router (api_handler)

def _list_zones(warehouse_id: str) -> tuple:
    """GET /warehouse/{id}/zones — list all zones with latest status."""
    wh_ref = db.collection("warehouses").document(warehouse_id)
    wh_doc = wh_ref.get()
    if not wh_doc.exists:
        return _json_response({"error": f"Warehouse '{warehouse_id}' not found."}, 404)

    zones = []
    for doc in wh_ref.collection("zones").stream():
        zone = doc.to_dict()
        zone["id"] = doc.id

        latest = doc.reference.collection("latest").document("current").get()
        if latest.exists:
            latest_data = latest.to_dict()
            if "timestamp" in latest_data and hasattr(latest_data["timestamp"], "isoformat"):
                latest_data["timestamp"] = latest_data["timestamp"].isoformat()
            zone["latest"] = latest_data
        else:
            zone["latest"] = None

        zones.append(zone)

    return _json_response(zones)


def _zone_summary(warehouse_id: str, zone_id: str) -> tuple:
    """GET /warehouse/{id}/zone/{zoneId}/summary — zone-level 24h stats."""
    zone_ref = (
        db.collection("warehouses").document(warehouse_id)
        .collection("zones").document(zone_id)
    )
    zone_doc = zone_ref.get()
    if not zone_doc.exists:
        return _json_response({"error": f"Zone '{zone_id}' not found."}, 404)

    since = datetime.utcnow() - timedelta(hours=24)
    readings = list(
        zone_ref.collection("readings")
        .where("timestamp", ">=", since)
        .order_by("timestamp")
        .stream()
    )

    if not readings:
        return _json_response({
            "warehouse_id": warehouse_id,
            "zone_id": zone_id,
            "readings_count": 0,
            "message": "No readings in the last 24 hours.",
        })

    temps = [r.to_dict().get("temperature", 0) for r in readings]
    hums  = [r.to_dict().get("humidity", 0) for r in readings]
    risks = [r.to_dict().get("riskScore", 0) for r in readings]

    return _json_response({
        "warehouse_id": warehouse_id,
        "zone_id": zone_id,
        "readings_count": len(readings),
        "temperature": {
            "avg": round(sum(temps) / len(temps), 2),
            "min": round(min(temps), 2),
            "max": round(max(temps), 2),
        },
        "humidity": {
            "avg": round(sum(hums) / len(hums), 2),
            "min": round(min(hums), 2),
            "max": round(max(hums), 2),
        },
        "risk_score": {
            "avg": round(sum(risks) / len(risks), 2),
            "max": round(max(risks), 2),
        },
    })
```

### Step 2: Update Router in `api_handler`

Add these routes to the existing `api_handler` function's routing logic:

```python
# Inside api_handler, after existing route matching:

    # Parse path segments
    parts = path.split("/")

    # ...existing routes...

    # GET /warehouse/{id}/zones                     (NEW)
    if (len(parts) == 4 and parts[1] == "warehouse"
            and parts[3] == "zones" and method == "GET"):
        return _list_zones(parts[2])

    # GET /warehouse/{id}/zone/{zoneId}/summary     (NEW)
    if (len(parts) == 5 and parts[1] == "warehouse"
            and parts[3] == "zone" and method == "GET"):
        return _zone_summary(parts[2], parts[4])

    # ...existing fallback...
```

### Step 3: Update Validation

```python
# filepath: backend/m2-backend/api-function/validate.py
# Add zone_id validation

import re

VALID_COMMODITIES = {"tomato", "potato", "banana", "rice", "onion"}
VALID_WAREHOUSE_PATTERN = r"^wh\d{3}$"
VALID_ZONE_PATTERN = r"^zone-[A-Z]$"     # NEW

FIELD_RULES = {
    "warehouse_id": {"type": str, "required": True},
    "zone_id":      {"type": str, "required": False, "default": "zone-A"},  # NEW
    "commodity_type": {"type": str, "required": True, "allowed": VALID_COMMODITIES},
    # ...existing rules...
}

def validate_zone_id(zone_id: str) -> list:
    """Validate zone_id format. Returns list of error strings."""
    errors = []
    if zone_id and not re.match(VALID_ZONE_PATTERN, zone_id):
        errors.append(f"zone_id '{zone_id}' must match pattern 'zone-[A-Z]'")
    return errors
```

### Step 4: Update Alert Function for Zone Context

```python
# filepath: backend/m2-backend/alert-function/main.py
# In _extract_fields, add:

def _extract_fields(cloud_event_data) -> dict:
    # ...existing code...
    fields["zone_id"] = _get_string(raw_fields, "zoneId") or "unknown"
    return fields


# In _format_sms, add zone label:
def _format_sms(fields: dict, lang: str = "hi") -> str:
    zone = fields.get("zone_id", "")
    zone_label = f" [{zone}]" if zone and zone != "unknown" else ""
    # ...existing code with zone_label appended to warehouse name...
```

### Step 5: Deploy

```bash
gcloud functions deploy postharvest-api \
  --gen2 --runtime=python311 --region=asia-south1 \
  --source=./api-function --entry-point=api_handler \
  --trigger-http --allow-unauthenticated \
  --memory=256MiB --timeout=60s
```

---

## Part 7 — Flutter App: Zone-Aware Dashboard

### Overview

The Flutter app is updated to:

1. **New model**: `Zone` model for zone documents
2. **Updated models**: `Reading` and `Alert` gain `zoneId` field
3. **New providers**: Zone streams, zone-level latest data, zone readings
4. **Updated UI**: Zone selector chips on warehouse detail, zone comparison grid

### Step 1: Create Zone Model

```dart
// filepath: mobile/lib/models/zone.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Zone {
  final String id;
  final String name;
  final String commodityType;
  final DateTime? createdAt;

  Zone({
    required this.id,
    required this.name,
    required this.commodityType,
    this.createdAt,
  });

  factory Zone.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Zone(
      id: doc.id,
      name: data['name'] ?? doc.id,
      commodityType: data['commodityType'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
```

### Step 2: Update Reading Model

Add `zoneId` field:

```dart
// filepath: mobile/lib/models/reading.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Reading {
  final String id;
  final String warehouseId;
  final String zoneId;          // NEW
  final double temperature;
  final double humidity;
  final double? co2Level;
  final double? ethyleneLevel;
  final double? riskScore;
  final String? riskLevel;
  final double? daysToSpoilage;
  final DateTime timestamp;

  Reading({
    required this.id,
    required this.warehouseId,
    this.zoneId = '',            // NEW
    required this.temperature,
    required this.humidity,
    this.co2Level,
    this.ethyleneLevel,
    this.riskScore,
    this.riskLevel,
    this.daysToSpoilage,
    required this.timestamp,
  });

  factory Reading.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Reading(
      id: doc.id,
      warehouseId: data['warehouseId'] ?? data['warehouse_id'] ?? '',
      zoneId: data['zoneId'] ?? data['zone_id'] ?? '',     // NEW
      temperature: (data['temperature'] ?? 0).toDouble(),
      humidity: (data['humidity'] ?? 0).toDouble(),
      co2Level: (data['co2'] ?? data['co2Level'])?.toDouble(),
      ethyleneLevel: (data['gasLevel'] ?? data['gas_level']
                     ?? data['ethyleneLevel'])?.toDouble(),
      riskScore: (data['riskScore'] ?? data['risk_score'])?.toDouble(),
      riskLevel: (data['riskLevel'] ?? data['risk_level'])?.toString(),
      daysToSpoilage: (data['daysToSpoilage']
                      ?? data['days_to_spoilage'])?.toDouble(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Reading.fromMap(Map<String, dynamic> data, {String id = ''}) {
    return Reading(
      id: id,
      warehouseId: data['warehouseId'] ?? data['warehouse_id'] ?? '',
      zoneId: data['zoneId'] ?? data['zone_id'] ?? '',     // NEW
      temperature: (data['temperature'] ?? 0).toDouble(),
      humidity: (data['humidity'] ?? 0).toDouble(),
      co2Level: (data['co2'] ?? data['co2Level'])?.toDouble(),
      ethyleneLevel: (data['gasLevel'] ?? data['gas_level'])?.toDouble(),
      riskScore: (data['riskScore'] ?? data['risk_score'])?.toDouble(),
      riskLevel: (data['riskLevel'] ?? data['risk_level'])?.toString(),
      daysToSpoilage: (data['daysToSpoilage']
                      ?? data['days_to_spoilage'])?.toDouble(),
      timestamp: DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}
```

### Step 3: Update Alert Model

Add `zoneId` field:

```dart
// filepath: mobile/lib/models/alert.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Alert {
  final String id;
  final String warehouseId;
  final String zoneId;          // NEW
  final String type;
  final String severity;
  final String message;
  final bool acknowledged;
  final DateTime timestamp;

  Alert({
    required this.id,
    this.warehouseId = '',
    this.zoneId = '',            // NEW
    required this.type,
    required this.severity,
    required this.message,
    this.acknowledged = false,
    required this.timestamp,
  });

  static String _extractWarehouseId(DocumentReference ref) {
    final segments = ref.path.split('/');
    final idx = segments.indexOf('warehouses');
    if (idx != -1 && idx + 1 < segments.length) return segments[idx + 1];
    return '';
  }

  factory Alert.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Alert(
      id: doc.id,
      warehouseId: data['warehouseId'] ?? _extractWarehouseId(doc.reference),
      zoneId: data['zoneId'] ?? '',                    // NEW
      type: data['type'] ?? '',
      severity: data['severity'] ?? 'warning',
      message: data['message'] ?? '',
      acknowledged: data['acknowledged'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory Alert.fromQueryDoc(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Alert(
      id: doc.id,
      warehouseId: data['warehouseId'] ?? _extractWarehouseId(doc.reference),
      zoneId: data['zoneId'] ?? '',                    // NEW
      type: data['type'] ?? '',
      severity: data['severity'] ?? 'warning',
      message: data['message'] ?? '',
      acknowledged: data['acknowledged'] ?? false,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
```

### Step 4: Add Zone Providers

```dart
// filepath: mobile/lib/providers/warehouse_providers.dart
// Add to existing file:

import '../models/zone.dart';      // NEW import

// ...existing providers...

// ═══════════════════════════════════════════════════════════════════════
// ZONE PROVIDERS (NEW)
// ═══════════════════════════════════════════════════════════════════════

/// Stream all zones for a warehouse
final zonesProvider = StreamProvider.family<List<Zone>, String>(
  (ref, warehouseId) {
    return FirebaseFirestore.instance
        .collection('warehouses/$warehouseId/zones')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => Zone.fromFirestore(doc)).toList());
  },
);

/// Stream latest sensor data for a specific zone
final zoneLatestProvider = StreamProvider.family<
  Map<String, dynamic>,
  ({String warehouseId, String zoneId})
>((ref, params) {
  return FirebaseFirestore.instance
      .doc('warehouses/${params.warehouseId}'
           '/zones/${params.zoneId}/latest/current')
      .snapshots()
      .map((snap) => snap.exists ? snap.data()! : <String, dynamic>{});
});

/// Stream zone-level reading history (for charts)
final zoneReadingsHistoryProvider = StreamProvider.family<
  List<Reading>,
  ({String warehouseId, String zoneId, String timeRange})
>((ref, params) {
  final now = DateTime.now();
  late DateTime startTime;

  switch (params.timeRange) {
    case '1h':
      startTime = now.subtract(const Duration(hours: 1));
      break;
    case '6h':
      startTime = now.subtract(const Duration(hours: 6));
      break;
    case '24h':
      startTime = now.subtract(const Duration(hours: 24));
      break;
    case '7d':
      startTime = now.subtract(const Duration(days: 7));
      break;
    case '30d':
      startTime = now.subtract(const Duration(days: 30));
      break;
    default:
      startTime = now.subtract(const Duration(hours: 24));
  }

  return FirebaseFirestore.instance
      .collection('warehouses/${params.warehouseId}'
                  '/zones/${params.zoneId}/readings')
      .where('timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startTime))
      .orderBy('timestamp', descending: false)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => Reading.fromFirestore(doc)).toList());
});
```

### Step 5: Add Zone Selection State

```dart
// filepath: mobile/lib/providers/ui_state_providers.dart
// Add to existing file:

/// Currently selected zone ID (null = warehouse aggregate view)
final selectedZoneIdProvider = StateProvider<String?>((ref) => null);
```

### Step 6: Update Warehouse Detail Screen

Add zone selector chips and zone comparison grid. Key changes:

```dart
// filepath: mobile/lib/screens/warehouse_detail_screen.dart

// In build():
// 1. Watch zonesProvider(warehouseId) and selectedZoneIdProvider
// 2. Switch latestData between zoneLatestProvider and latestReadingProvider
//    based on whether a zone is selected
// 3. Add ChoiceChip row for "All Zones" + individual zone chips
// 4. Add _ZoneComparisonGrid widget when no zone is selected

// Example zone selector:
zonesAsync.when(
  data: (zones) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All Zones'),
            selected: selectedZone == null,
            onSelected: (_) {
              ref.read(selectedZoneIdProvider.notifier).state = null;
            },
          ),
          ...zones.map((zone) => ChoiceChip(
            label: Text(zone.name),
            selected: selectedZone == zone.id,
            onSelected: (_) {
              ref.read(selectedZoneIdProvider.notifier).state = zone.id;
            },
          )),
        ],
      ),
    );
  },
  // ...
);
```

### Step 7: Update Alert Tile for Zone Label

In `mobile/lib/widgets/alert_tile.dart`, display `alert.zoneId` if non-empty:

```dart
if (alert.zoneId.isNotEmpty) ...[
  const SizedBox(width: 6),
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.blue.withAlpha(20),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(alert.zoneId, style: TextStyle(fontSize: 10)),
  ),
],
```

### Step 8: Update Notification Service for Zone Topics

```dart
// filepath: mobile/lib/services/notification_service.dart
// Add zone-level topic subscription:

Future<void> subscribeToZone(String warehouseId, String zoneId) {
  return _messaging.subscribeToTopic('warehouse_${warehouseId}_$zoneId');
}

Future<void> unsubscribeFromZone(String warehouseId, String zoneId) {
  return _messaging.unsubscribeFromTopic('warehouse_${warehouseId}_$zoneId');
}
```

---

## Part 8 — Testing, Simulator, & Demo Scripts

### Step 1: Update Test Fixtures

```python
# filepath: backend/m2-backend/tests/conftest.py
# Update seed_warehouse to include zones

@pytest.fixture
def seed_warehouse(firestore_client):
    """Seed a warehouse WITH zones for testing."""
    wh_id = "wh001"
    wh_ref = firestore_client.collection("warehouses").document(wh_id)
    wh_ref.set({
        "name": "Test Cold Storage",
        "location": "Ludhiana, Punjab",
        "commodityType": "tomato",
        "capacity": 500,
        "zoneCount": 2,
        "ownerId": "test-user-001",
    })

    # Warehouse-level latest (aggregate)
    wh_ref.collection("latest").document("current").set({
        "temperature": 28.5,
        "humidity": 72.0,
        "co2": 450.0,
        "gasLevel": 0.2,
        "riskScore": 45.0,
        "riskLevel": "medium",
        "daysToSpoilage": 5.5,
        "estimatedLossInr": 12000.0,
        "commodityType": "tomato",
        "zoneCount": 2,
        "timestamp": datetime.datetime.utcnow(),
    })

    # Zone A
    zone_a = wh_ref.collection("zones").document("zone-A")
    zone_a.set({"name": "Front Section", "commodityType": "tomato"})
    zone_a.collection("latest").document("current").set({
        "temperature": 26.0, "humidity": 75.0, "co2": 420.0,
        "gasLevel": 0.15, "riskScore": 35.0, "riskLevel": "medium",
        "daysToSpoilage": 6.0, "zoneId": "zone-A",
        "timestamp": datetime.datetime.utcnow(),
    })

    # Zone B
    zone_b = wh_ref.collection("zones").document("zone-B")
    zone_b.set({"name": "Loading Dock", "commodityType": "tomato"})
    zone_b.collection("latest").document("current").set({
        "temperature": 31.0, "humidity": 68.0, "co2": 480.0,
        "gasLevel": 0.3, "riskScore": 65.0, "riskLevel": "high",
        "daysToSpoilage": 3.5, "zoneId": "zone-B",
        "timestamp": datetime.datetime.utcnow(),
    })

    yield wh_id

    _cleanup_warehouse(firestore_client, wh_id)
```

### Step 2: Update `_cleanup_warehouse`

```python
# filepath: backend/m2-backend/tests/conftest.py

def _cleanup_warehouse(client, wh_id):
    """Remove a warehouse and all its subcollections."""
    wh_ref = client.collection("warehouses").document(wh_id)
    for sub in ("latest", "readings", "predictions", "alerts"):
        _delete_collection(wh_ref.collection(sub))
    # Clean zones (NEW)
    for zone_doc in wh_ref.collection("zones").stream():
        for zone_sub in ("latest", "readings"):
            _delete_collection(zone_doc.reference.collection(zone_sub))
        zone_doc.reference.delete()
    wh_ref.delete()
```

### Step 3: Add Zone API Tests

```python
# filepath: backend/m2-backend/tests/test_api_function.py

class TestZoneEndpoints:

    @pytest.mark.integration
    def test_list_zones(self, seed_warehouse):
        """GET /warehouse/wh001/zones should return zone list."""
        resp = api_handler(_make_request("GET", "/warehouse/wh001/zones"))
        data, status, _ = _parse_response(resp)
        assert status == 200
        assert isinstance(data, list)
        assert len(data) >= 2
        zone_ids = [z["id"] for z in data]
        assert "zone-A" in zone_ids
        assert "zone-B" in zone_ids
        for z in data:
            assert "latest" in z

    @pytest.mark.integration
    def test_zone_summary_empty(self, seed_warehouse):
        """GET zone summary with no readings returns count 0."""
        resp = api_handler(
            _make_request("GET", "/warehouse/wh001/zone/zone-A")
        )
        data, status, _ = _parse_response(resp)
        assert status == 200
        assert data["zone_id"] == "zone-A"
```

### Step 4: Batch + Encrypted Simulator

```python
# filepath: scripts/simulator.py
"""
Updated simulator with batch + encryption support for demo.

Modes:
  --mode encrypted    → AES-128-CBC encrypted protobuf batch
  --mode batch        → Plaintext JSON batch
  --mode single       → Legacy single readings (backward compat)
"""

import argparse
import base64
import json
import os
import random
import time
from datetime import datetime

import requests

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives import padding as crypto_padding
    CRYPTO_AVAILABLE = True
except ImportError:
    CRYPTO_AVAILABLE = False
    print("⚠ cryptography not installed — encrypted mode unavailable")

# ── Configuration ─────────────────────────────────────────────────────
FUNCTION_URL = "https://predict-spoilage-n6hvbwpdfq-el.a.run.app"
WAREHOUSE_ID = "wh001"
ZONE_ID      = "zone-A"
COMMODITY    = "tomato"
INTERVAL_SEC = 5
TOTAL_POSTS  = 120
BATCH_SIZE   = 10

# AES-128 key (must match Cloud Function)
AES_KEY = bytes.fromhex("0102030405060708090a0b0c0d0e0f10")

BASE_TEMP = 14.0
BASE_HUM  = 90.0
TEMP_DRIFT = 0.12
HUM_DRIFT  = -0.08


def encrypt_batch(readings: list) -> tuple:
    """Encrypt a list of reading dicts using AES-128-CBC.

    Returns (iv_b64, ciphertext_b64).
    """
    if not CRYPTO_AVAILABLE:
        raise RuntimeError("cryptography package not installed")

    plaintext = json.dumps(readings).encode("utf-8")
    iv = os.urandom(16)

    padder = crypto_padding.PKCS7(128).padder()
    padded = padder.update(plaintext) + padder.finalize()

    cipher = Cipher(algorithms.AES(AES_KEY), modes.CBC(iv))
    encryptor = cipher.encryptor()
    ciphertext = encryptor.update(padded) + encryptor.finalize()

    return (
        base64.b64encode(iv).decode(),
        base64.b64encode(ciphertext).decode(),
    )


def run(url, warehouse, zone, commodity, interval, total, batch_size, mode):
    hours = 24.0
    reading_num = 0
    num_batches = total // batch_size if mode != "single" else total

    print(f"\n{'='*60}")
    print(f"  PostHarvest Simulator — {mode.upper()} mode")
    print(f"  URL:       {url}")
    print(f"  Target:    {warehouse}/{zone}")
    print(f"  Commodity: {commodity}")
    if mode != "single":
        print(f"  Batch:     {batch_size} readings × {num_batches} batches")
    else:
        print(f"  Readings:  {total}")
    print(f"{'='*60}\n")

    for batch_num in range(num_batches):
        readings = []
        for i in range(batch_size if mode != "single" else 1):
            reading_num += 1
            noise_t = random.gauss(0, 0.3)
            noise_h = random.gauss(0, 0.5)

            temp = round(BASE_TEMP + TEMP_DRIFT * reading_num + noise_t, 2)
            hum  = round(
                max(0, min(100, BASE_HUM + HUM_DRIFT * reading_num + noise_h)),
                2,
            )
            hours += 168.0 / total

            reading = {
                "temperature": temp,
                "humidity": hum,
                "co2": round(420 + reading_num * 1.5 + random.gauss(0, 5), 1),
                "gas_level": round(
                    max(0, 50 + reading_num * 0.3 + random.gauss(0, 2)), 1
                ),
                "hours_in_storage": round(hours, 2),
            }
            readings.append(reading)

        try:
            if mode == "encrypted":
                iv_b64, ct_b64 = encrypt_batch(readings)
                payload = {
                    "warehouse_id": warehouse,
                    "zone_id": zone,
                    "commodity_type": commodity,
                    "batch_size": len(readings),
                    "encrypted": True,
                    "iv": iv_b64,
                    "ciphertext": ct_b64,
                }
                resp = requests.post(url, json=payload, timeout=30)
                result = resp.json()
                processed = result.get("processed", 0)
                print(
                    f"  🔐 Batch {batch_num+1}/{num_batches}: "
                    f"{processed}/{len(readings)} processed "
                    f"| HTTP {resp.status_code}"
                )

            elif mode == "batch":
                payload = {
                    "warehouse_id": warehouse,
                    "zone_id": zone,
                    "commodity_type": commodity,
                    "batch": True,
                    "readings": readings,
                }
                resp = requests.post(url, json=payload, timeout=30)
                result = resp.json()
                processed = result.get("processed", 0)
                print(
                    f"  📦 Batch {batch_num+1}/{num_batches}: "
                    f"{processed}/{len(readings)} processed "
                    f"| HTTP {resp.status_code}"
                )

            else:  # single
                r = readings[0]
                payload = {
                    "warehouse_id": warehouse,
                    "zone_id": zone,
                    "commodity_type": commodity,
                    **r,
                }
                resp = requests.post(url, json=payload, timeout=10)
                result = resp.json()
                risk = result.get("risk_level", "?")
                print(
                    f"  📡 Reading {reading_num}: T={r['temperature']}°C "
                    f"H={r['humidity']}% → {risk} | HTTP {resp.status_code}"
                )

        except Exception as e:
            print(f"  ❌ ERROR: {e}")

        time.sleep(interval)

    print(f"\n✅ Done — {reading_num} readings sent.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="PostHarvest Simulator")
    parser.add_argument("--url", default=FUNCTION_URL)
    parser.add_argument("--warehouse", default=WAREHOUSE_ID)
    parser.add_argument("--zone", default=ZONE_ID)
    parser.add_argument(
        "--commodity", default=COMMODITY,
        choices=["tomato", "potato", "banana", "rice", "onion"],
    )
    parser.add_argument("--interval", type=int, default=INTERVAL_SEC)
    parser.add_argument("--total", type=int, default=TOTAL_POSTS)
    parser.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    parser.add_argument(
        "--mode", default="encrypted",
        choices=["encrypted", "batch", "single"],
    )
    args = parser.parse_args()

    run(
        args.url, args.warehouse, args.zone, args.commodity,
        args.interval, args.total, args.batch_size, args.mode,
    )
```

### Step 5: Run Tests

```bash
# Start emulators
firebase emulators:start --only firestore

# Run all tests
cd backend/m2-backend
python -m pytest tests/ -v --tb=short

# Run E2E only
python -m pytest tests/test_e2e.py -m e2e -v
```

### Step 6: Demo Seeding (multi-zone)

```bash
# Seed zone-A (tomato, normal → degrading)
python scripts/simulator.py --mode encrypted --zone zone-A --total 60

# Seed zone-B (potato, different conditions)
python scripts/simulator.py --mode encrypted --zone zone-B \
    --commodity potato --total 60

# Seed zone-C (tomato, different drift)
python scripts/simulator.py --mode encrypted --zone zone-C --total 60
```

---

## Implementation Order Summary

| Phase | Part | What | Effort |
|-------|------|------|--------|
| 1 | **Part 1** | Firestore schema + indexes + security rules | 1h |
| 2 | **Part 2** | Proto definitions + AES crypto module | 1.5h |
| 3 | **Part 5** | Cloud Function (decrypt + batch predict + zone write) | 2.5h |
| 4 | **Part 4** | Gateway update (zero-knowledge relay) | 30m |
| 5 | **Part 3** | ESP32 firmware (batch + AES + protobuf) | 2h |
| 6 | **Part 6** | Backend API zone endpoints | 1h |
| 7 | **Part 7** | Flutter zone UI + models + providers | 2.5h |
| 8 | **Part 8** | Tests + simulator + demo seeding | 1.5h |

**Total estimated effort: ~12-13 hours**

### Backward Compatibility

All changes are **additive**:

- Single-reading mode still works (Cloud Function detects `encrypted` / `batch` flags)
- Warehouse-level `readings/` and `latest/current` still written
- `zone_id` defaults to `"zone-A"` everywhere if not provided
- Existing ESP32 firmware continues to work through the gateway's legacy path
