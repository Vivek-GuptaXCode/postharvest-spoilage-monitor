# Backend — PostHarvest IoT Alert & API System

**CU NextGenHack 2026 · PS 12: IoT-Based Post-Harvest Storage Loss Prediction System**

Member: M2 — Backend API Engineer & Multi-Channel Notification Architect

---

## Project Structure

```
m2-backend/
├── alert-function/              # Firestore-triggered → SMS + Telegram
│   ├── main.py                  # Cloud Function entry point (on_alert_created)
│   ├── requirements.txt
│   └── alert_templates.py       # Hindi/English message templates
├── api-function/                # REST API endpoints for Flutter app
│   ├── main.py                  # Cloud Function entry point (api_handler)
│   ├── requirements.txt
│   └── validate.py              # Shared validation (copy to M1's cloud-function/)
├── scripts/
│   ├── simulator.py             # Hardware failure fallback — posts degrading data
│   ├── seed_historical.py       # Pre-seed 24h data for demo charts
│   └── test_integration.py      # End-to-end integration tests (pytest)
├── firestore.rules              # Firestore Security Rules for Flutter app
├── .gitignore
└── README.md                    # This file
```

---

## Quick-Start Deploy Commands

Replace placeholder values (`ACXXX`, `+1XXX`, etc.) with actual credentials before deploying.

### 1. Deploy Firestore Security Rules

```bash
firebase deploy --only firestore:rules
```

### 2. Deploy Alert Notification Function (Firestore-triggered)

```bash
# Grant Eventarc service agent the receiver role (one-time)
PROJECT_NUMBER=$(gcloud projects describe postharvest-hack --format='value(projectNumber)')

gcloud projects add-iam-policy-binding postharvest-hack \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver"

# Deploy the function
gcloud functions deploy send-alert-notification \
  --gen2 \
  --runtime=python311 \
  --region=asia-south1 \
  --source=./alert-function \
  --entry-point=on_alert_created \
  --trigger-event-filters="type=google.cloud.firestore.document.v1.created" \
  --trigger-event-filters="database=(default)" \
  --trigger-event-filters-path-pattern="document=warehouses/{warehouseId}/alerts/{alertId}" \
  --trigger-location=asia-south1 \
  --memory=256MiB \
  --timeout=30s \
  --set-env-vars="\
TWILIO_ACCOUNT_SID=ACXXX,\
TWILIO_AUTH_TOKEN=XXX,\
TWILIO_PHONE_NUMBER=+1XXX,\
ALERT_PHONE_NUMBERS=+91XXX,\
TELEGRAM_BOT_TOKEN=XXX,\
TELEGRAM_CHAT_ID=XXX,\
ALERT_LANGUAGE=both"
```

### 3. Deploy REST API Function (HTTP-triggered)

```bash
gcloud functions deploy postharvest-api \
  --gen2 \
  --runtime=python311 \
  --region=asia-south1 \
  --source=./api-function \
  --entry-point=api_handler \
  --trigger-http \
  --allow-unauthenticated \
  --memory=256MiB \
  --timeout=60s
```

### 4. Get Deployed URLs

```bash
# M2's REST API URL → share with M4
API_URL=$(gcloud functions describe postharvest-api \
  --gen2 --region=asia-south1 \
  --format='value(serviceConfig.uri)')
echo "API URL: $API_URL"

# M1's predict-spoilage URL → needed for simulator & tests
PREDICT_URL=$(gcloud functions describe predict-spoilage \
  --gen2 --region=asia-south1 \
  --format='value(serviceConfig.uri)')
echo "Predict URL: $PREDICT_URL"
```

### 5. Run Integration Tests

```bash
pip install pytest requests
PREDICT_URL="https://..." API_URL="https://..." pytest scripts/test_integration.py -v --tb=short
```

### 6. Seed Historical Data (24h for demo charts)

```bash
pip install requests
python scripts/seed_historical.py --url "https://PREDICT_SPOILAGE_URL"
```

### 7. Run Simulator (demo fallback if hardware fails)

```bash
python scripts/simulator.py --url "https://PREDICT_SPOILAGE_URL" --commodity tomato --interval 5
```

---

## API Endpoint Reference (share with M4)

| Method | Path | Description | Response |
|--------|------|-------------|----------|
| `GET` | `/health` | Health check | `{"status":"healthy","timestamp":"..."}` |
| `GET` | `/warehouses` | All warehouses + latest readings + unack alert count | `[{"id":"wh001","name":"...","latest":{...},"unacknowledged_alerts":2}]` |
| `GET` | `/warehouse/{id}/summary` | Aggregated 24h stats for one warehouse | `{"warehouse_id":"wh001","temperature":{"avg":...,"min":...,"max":...},...}` |
| `GET` | `/warehouse/{id}/export?hours=24` | CSV download of readings | CSV file attachment |
| `POST` | `/alerts/{warehouseId}/{alertId}/acknowledge` | Acknowledge an alert | `{"status":"acknowledged","alert_id":"..."}` |

---

## Integration with Other Members

### From M1 (AI/ML + GCP)
- **predict-spoilage Cloud Function URL** — needed by simulator, seeder, tests
- **Firestore schema** — field names: `temperature`, `humidity`, `co2`, `gasLevel`, `riskScore`, `riskLevel`, `daysToSpoilage`, `recommendation`, `estimatedLossInr`, `timestamp`, `imageUrl`
- **Firebase project ID**: `postharvest-hack`

### To M1
- **validate.py** — copy `api-function/validate.py` into M1's `cloud-function/` directory

### To M4 (Flutter)
- **REST API URL** (from step 4 above)
- **API endpoint reference** (table above)
- **Firestore Security Rules** (deployed in step 1)

### Notification Channels

| Channel | Technology | Cost | Language |
|---------|-----------|------|----------|
| Push (FCM) | M1 handles | Free | English |
| SMS | Twilio (M2) | Free trial | Hindi |
| Telegram | Bot API (M2) | Free forever | English |
| WhatsApp | Twilio Sandbox (M2 stretch) | Free trial | English |

---

## Environment Variables for Alert Function

| Variable | Description | Example |
|----------|-------------|---------|
| `TWILIO_ACCOUNT_SID` | Twilio Account SID | `ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `TWILIO_AUTH_TOKEN` | Twilio Auth Token | `xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx` |
| `TWILIO_PHONE_NUMBER` | Twilio trial phone number | `+14155238886` |
| `ALERT_PHONE_NUMBERS` | Comma-separated verified numbers | `+91XXXXXXXXXX,+91YYYYYYYYYY` |
| `TELEGRAM_BOT_TOKEN` | Telegram Bot API token | `7123456789:AAF...` |
| `TELEGRAM_CHAT_ID` | Telegram chat/group ID | `123456789` or `-100123456789` |
| `ALERT_LANGUAGE` | `en`, `hi`, or `both` | `both` |
| `WHATSAPP_ENABLED` | Enable WhatsApp sandbox | `false` |
