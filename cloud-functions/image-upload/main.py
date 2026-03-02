"""
Cloud Function (2nd gen, HTTP trigger) — ESP32-CAM Image Upload.

Receives a base64-encoded JPEG from the ESP32, writes it to Cloud Storage,
makes it publicly accessible, and updates Firestore with the public URL.

Endpoint: POST  /upload-image
Payload : {"warehouse_id": "wh001", "image": "<base64-jpeg>"}
Response: {"image_url": "https://...", "warehouse_id": "...", "filename": "..."}
"""

import base64
import datetime
import json
import functions_framework
from flask import jsonify, make_response

from google.cloud import storage
from google.cloud import firestore

# ── Constants ─────────────────────────────────────────────────────────
GCS_BUCKET = "postharvest-hack-esp32cam-images"
MAX_IMAGE_BYTES = 200_000          # 200 KB decoded max (VGA JPEG is 30-50 KB)
MAX_BASE64_CHARS = MAX_IMAGE_BYTES * 4 // 3 + 100  # ~267 KB base64 string

# ── Lazy-initialized clients (reused across invocations) ─────────────
_storage_client = None
_firestore_client = None


def _get_storage():
    global _storage_client
    if _storage_client is None:
        _storage_client = storage.Client()
    return _storage_client


def _get_firestore():
    global _firestore_client
    if _firestore_client is None:
        _firestore_client = firestore.Client()
    return _firestore_client


# ── CORS helper ───────────────────────────────────────────────────────
def _cors_response(response, status=200):
    """Wrap a flask response with CORS headers."""
    resp = make_response(response, status)
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return resp


# ═════════════════════════════════════════════════════════════════════
# MAIN HANDLER
# ═════════════════════════════════════════════════════════════════════

@functions_framework.http
def upload_image_handler(request):
    """HTTP Cloud Function entry point."""

    # ── CORS preflight ────────────────────────────────────────────────
    if request.method == "OPTIONS":
        return _cors_response("", 204)

    if request.method != "POST":
        return _cors_response(
            jsonify({"error": "Only POST is accepted"}), 405
        )

    # ── Parse JSON body ───────────────────────────────────────────────
    try:
        data = request.get_json(force=True)
    except Exception:
        return _cors_response(
            jsonify({"error": "Invalid JSON body"}), 400
        )

    if not data:
        return _cors_response(
            jsonify({"error": "Empty request body"}), 400
        )

    warehouse_id = data.get("warehouse_id", "").strip()
    image_b64 = data.get("image", "").strip()
    commodity_type = data.get("commodity_type", "")

    # ── Validate ──────────────────────────────────────────────────────
    if not warehouse_id:
        return _cors_response(
            jsonify({"error": "Missing 'warehouse_id'"}), 400
        )

    if not image_b64:
        return _cors_response(
            jsonify({"error": "Missing 'image' (base64-encoded JPEG)"}), 400
        )

    if len(image_b64) > MAX_BASE64_CHARS:
        return _cors_response(
            jsonify({
                "error": f"Image too large. Max {MAX_IMAGE_BYTES} bytes decoded."
            }), 413
        )

    # ── Decode base64 → raw JPEG bytes ────────────────────────────────
    try:
        image_bytes = base64.b64decode(image_b64, validate=True)
    except Exception as e:
        return _cors_response(
            jsonify({"error": f"Base64 decode failed: {e}"}), 400
        )

    if len(image_bytes) > MAX_IMAGE_BYTES:
        return _cors_response(
            jsonify({
                "error": f"Decoded image is {len(image_bytes)} bytes, "
                         f"max allowed is {MAX_IMAGE_BYTES}."
            }), 413
        )

    # Quick JPEG magic-byte check (FFD8)
    if len(image_bytes) < 2 or image_bytes[0:2] != b"\xff\xd8":
        return _cors_response(
            jsonify({"error": "Image does not appear to be a valid JPEG."}), 400
        )

    # ── Upload to Cloud Storage ───────────────────────────────────────
    now = datetime.datetime.utcnow()
    timestamp_str = now.strftime("%Y%m%d_%H%M%S")
    filename = f"{warehouse_id}/{timestamp_str}.jpg"

    try:
        bucket = _get_storage().bucket(GCS_BUCKET)
        blob = bucket.blob(filename)
        blob.upload_from_string(image_bytes, content_type="image/jpeg")
        blob.make_public()
        public_url = blob.public_url
    except Exception as e:
        return _cors_response(
            jsonify({"error": f"Cloud Storage upload failed: {e}"}), 500
        )

    # ── Update Firestore (merge — don't clobber sensor data) ─────────
    try:
        doc_ref = _get_firestore().document(
            f"warehouses/{warehouse_id}/latest/current"
        )
        doc_ref.set(
            {
                "imageUrl": public_url,
                "imageTimestamp": now.isoformat() + "Z",
            },
            merge=True,  # CRITICAL: only touch image fields
        )
    except Exception as e:
        # Image is already uploaded — log but don't fail the whole request
        print(f"WARNING: Firestore update failed: {e}")

    # ── Success response ──────────────────────────────────────────────
    result = {
        "image_url": public_url,
        "warehouse_id": warehouse_id,
        "filename": filename,
        "size_bytes": len(image_bytes),
        "timestamp": now.isoformat() + "Z",
    }
    print(f"Image uploaded: {filename} ({len(image_bytes)} bytes)")

    return _cors_response(jsonify(result), 200)
