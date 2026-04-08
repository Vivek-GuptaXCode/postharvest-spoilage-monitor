"""
Cloud Function (2nd gen, Firestore trigger) — Multi-Channel Alert Dispatcher.

Triggered by: document creation in warehouses/{warehouseId}/alerts/{alertId}
Sends: Twilio SMS (Hindi) + Telegram Bot (English) + optional WhatsApp

Consistency notes:
  - M1's predict-spoilage function creates alert docs with fields:
        type, severity, message, timestamp, acknowledged
  - M4's Flutter app reads alerts from warehouses/{id}/alerts subcollection
  - Firestore Eventarc payload uses google.cloud.firestore.document.v1.created
"""

import os
import json
import requests as http_requests
import functions_framework
from cloudevents.http import CloudEvent
from google.events.cloud import firestore as firestore_ev

# ── Configuration from environment variables ──────────────────────────
TWILIO_SID        = os.environ.get("TWILIO_ACCOUNT_SID", "")
TWILIO_TOKEN      = os.environ.get("TWILIO_AUTH_TOKEN", "")
TWILIO_FROM       = os.environ.get("TWILIO_PHONE_NUMBER", "")
ALERT_PHONES      = os.environ.get("ALERT_PHONE_NUMBERS", "").split(",")
TELEGRAM_TOKEN    = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID  = os.environ.get("TELEGRAM_CHAT_ID", "")
ALERT_LANGUAGE    = os.environ.get("ALERT_LANGUAGE", "both")  # "en", "hi", "both"
WHATSAPP_ENABLED  = os.environ.get("WHATSAPP_ENABLED", "false").lower() == "true"

# ── Lazy-load Twilio to avoid import if not configured ────────────────
_twilio_client = None


def _get_twilio():
    """Return a cached Twilio client, or None if credentials are missing."""
    global _twilio_client
    if _twilio_client is None and TWILIO_SID:
        from twilio.rest import Client
        _twilio_client = Client(TWILIO_SID, TWILIO_TOKEN)
    return _twilio_client


# ── Alert template (inline lightweight version) ──────────────────────
def _format_sms(fields: dict, lang: str = "hi") -> str:
    """Short SMS-friendly message (≤ 160 chars for English, ≤ 70 for Hindi segment)."""
    severity = fields.get("severity", "warning")
    message  = fields.get("message", "Spoilage risk detected.")
    wh       = fields.get("warehouse_id", "Unknown")
    zone     = fields.get("zone_id", "")
    zone_label = f" [{zone}]" if zone and zone != "unknown" else ""

    if lang == "hi":
        return (
            f"🚨 गंभीर चेतावनी — {wh}{zone_label}\n"
            f"{message}\n"
            f"⏰ तुरंत कार्रवाई करें!"
        )
    return f"🚨 ALERT [{severity.upper()}] — {wh}{zone_label}\n{message}"


def _format_telegram(fields: dict) -> str:
    """Rich Telegram message with HTML formatting."""
    severity = fields.get("severity", "warning")
    message  = fields.get("message", "")
    wh       = fields.get("warehouse_id", "")
    zone     = fields.get("zone_id", "")
    zone_label = f" • {zone}" if zone and zone != "unknown" else ""
    emoji    = "🚨" if severity == "critical" else "⚠️"

    return (
        f"{emoji} <b>{severity.upper()} ALERT</b>\n"
        f"📍 <b>Warehouse:</b> {wh}{zone_label}\n"
        f"📋 {message}\n\n"
        f"<i>— PostHarvest Alert Bot</i>"
    )


# ── Parsers for Firestore Eventarc payload ────────────────────────────
def _parse_string(field: dict) -> str:
    """Extract string value from Firestore Eventarc field."""
    return field.get("stringValue", "")


def _parse_float(field: dict) -> float:
    """Extract numeric value from Firestore Eventarc field."""
    return float(field.get("doubleValue", field.get("integerValue", 0)))


def _parse_bool(field: dict) -> bool:
    """Extract boolean value from Firestore Eventarc field."""
    return field.get("booleanValue", False)


def _extract_fields(cloud_event_data) -> dict:
    """Extract typed fields from the Firestore Eventarc document payload.

    In production (Gen 2), cloud_event.data arrives as protobuf bytes
    (DocumentEventData). We deserialize it, then extract fields.
    In local tests, it may arrive as a dict — handle both.

    Field names match M1's alert_doc schema in predict-spoilage:
      type, severity, message, timestamp, acknowledged
    """
    # ── Deserialize protobuf if data is bytes ─────────────────────────
    if isinstance(cloud_event_data, bytes):
        payload = firestore_ev.DocumentEventData()
        payload._pb.ParseFromString(cloud_event_data)

        doc_name = payload.value.name
        # Convert protobuf MapComposite fields to a plain dict
        fields = {}
        for key, val in payload.value.fields.items():
            # Determine the active value type via the raw protobuf descriptor.
            # proto-plus wrappers don't expose WhichOneof — use val._pb.
            raw = val._pb if hasattr(val, "_pb") else val
            kind = raw.WhichOneof("value_type") if hasattr(raw, "WhichOneof") else None

            if kind == "string_value":
                fields[key] = {"stringValue": val.string_value}
            elif kind == "boolean_value":
                fields[key] = {"booleanValue": val.boolean_value}
            elif kind == "double_value":
                fields[key] = {"doubleValue": val.double_value}
            elif kind == "integer_value":
                fields[key] = {"integerValue": val.integer_value}
            else:
                fields[key] = {}
    else:
        # Dict format (local emulator / tests)
        value  = cloud_event_data.get("value", {})
        fields = value.get("fields", {})
        doc_name = value.get("name", "")

    # Extract the warehouse ID from the document path
    # Path: projects/.../warehouses/{warehouseId}/alerts/{alertId}
    parts = doc_name.split("/")
    warehouse_id = ""
    for i, part in enumerate(parts):
        if part == "warehouses" and i + 1 < len(parts):
            warehouse_id = parts[i + 1]
            break

    return {
        "severity":      _parse_string(fields.get("severity", {})),
        "message":       _parse_string(fields.get("message", {})),
        "type":          _parse_string(fields.get("type", {})),
        "acknowledged":  _parse_bool(fields.get("acknowledged", {})),
        "warehouse_id":  warehouse_id,
        "zone_id":       _parse_string(fields.get("zoneId", {})) or "unknown",
    }


# ═══════════════════════════════════════════════════════════════════════
# MAIN HANDLER
# ═══════════════════════════════════════════════════════════════════════

@functions_framework.cloud_event
def on_alert_created(cloud_event: CloudEvent):
    """Triggered when a new alert document is created in Firestore.

    The trigger path pattern is:
        warehouses/{warehouseId}/alerts/{alertId}

    This is set via --trigger-event-filters-path-pattern at deploy time.
    Only warning + critical severity alerts produce external notifications.
    """

    fields = _extract_fields(cloud_event.data)
    severity = fields["severity"]
    print(f"[Alert] severity={severity}  warehouse={fields['warehouse_id']}  type={fields['type']}")

    # Only send external notifications for warning + critical
    if severity not in ("warning", "critical"):
        print("[Alert] Severity below threshold — skipping notification.")
        return

    # ── Telegram (always, free, fast) ─────────────────────────────────
    if TELEGRAM_TOKEN and TELEGRAM_CHAT_ID:
        try:
            tg_text = _format_telegram(fields)
            resp = http_requests.post(
                f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage",
                json={
                    "chat_id": TELEGRAM_CHAT_ID,
                    "text": tg_text,
                    "parse_mode": "HTML",
                },
                timeout=5,
            )
            print(f"[Telegram] sent — status {resp.status_code}")
        except Exception as e:
            print(f"[Telegram] ERROR: {e}")

    # ── SMS via Twilio (Hindi for critical, English for warning) ──────
    twilio = _get_twilio()
    if twilio and ALERT_PHONES:
        lang = "hi" if ALERT_LANGUAGE in ("hi", "both") else "en"
        sms_body = _format_sms(fields, lang=lang)

        # For "both" mode: send Hindi SMS (rural farmer persona)
        for phone in ALERT_PHONES:
            phone = phone.strip()
            if not phone:
                continue
            try:
                msg = twilio.messages.create(
                    body=sms_body,
                    from_=TWILIO_FROM,
                    to=phone,
                )
                print(f"[SMS] sent to {phone} — SID {msg.sid}")
            except Exception as e:
                print(f"[SMS] ERROR to {phone}: {e}")

    # ── WhatsApp via Twilio Sandbox (stretch goal) ────────────────────
    if WHATSAPP_ENABLED and twilio and ALERT_PHONES:
        wa_body = _format_sms(fields, lang="en")
        for phone in ALERT_PHONES:
            phone = phone.strip()
            if not phone:
                continue
            try:
                msg = twilio.messages.create(
                    body=wa_body,
                    from_="whatsapp:" + TWILIO_FROM,
                    to="whatsapp:" + phone,
                )
                print(f"[WhatsApp] sent to {phone} — SID {msg.sid}")
            except Exception as e:
                print(f"[WhatsApp] ERROR to {phone}: {e}")

    print("[Alert] Notification dispatch complete.")
