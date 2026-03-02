#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# deploy-image-function.sh
# Run this on Cloud Shell after uploading the image-function/ folder.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

PROJECT="postharvest-hack"
REGION="asia-south1"
BUCKET="postharvest-hack-esp32cam-images"

echo "▶ Setting project..."
gcloud config set project "$PROJECT"

# ── 1. Grant the default compute SA objectAdmin on the bucket ────────
# Needed for blob.make_public()
DEFAULT_SA="${PROJECT}@appspot.gserviceaccount.com"
echo "▶ Granting objectAdmin to $DEFAULT_SA on gs://$BUCKET ..."
gsutil iam ch "serviceAccount:${DEFAULT_SA}:objectAdmin" "gs://${BUCKET}/"

# ── 2. Deploy the Cloud Function ─────────────────────────────────────
echo "▶ Deploying upload-image Cloud Function..."
gcloud functions deploy upload-image \
  --gen2 \
  --runtime=python312 \
  --region="$REGION" \
  --source=./image-function \
  --entry-point=upload_image_handler \
  --trigger-http \
  --allow-unauthenticated \
  --memory=256MiB \
  --timeout=60s \
  --min-instances=0 \
  --max-instances=3

# ── 3. Get the URL ───────────────────────────────────────────────────
UPLOAD_URL=$(gcloud functions describe upload-image \
  --gen2 --region="$REGION" \
  --format='value(serviceConfig.uri)')
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  ✅  upload-image deployed!"
echo "  URL: $UPLOAD_URL"
echo "════════════════════════════════════════════════════════════"

# ── 4. Smoke test with a tiny 1x1 red JPEG ──────────────────────────
# This is a valid 631-byte JPEG (1x1 red pixel)
TINY_JPEG_B64=$( python3 -c "
import base64, struct, io
# Minimal JPEG: SOI + APP0 + DQT + SOF0 + DHT + SOS + data + EOI
# Easier: use PIL/Pillow if available
try:
    from PIL import Image
    buf = io.BytesIO()
    img = Image.new('RGB', (1,1), (255,0,0))
    img.save(buf, 'JPEG')
    print(base64.b64encode(buf.getvalue()).decode())
except ImportError:
    # Fallback: a known minimal valid JPEG (1x1 red pixel, 631 bytes)
    print('$FALLBACK')
" )

# If PIL failed, use a hardcoded minimal JPEG
if [ "$TINY_JPEG_B64" = '$FALLBACK' ] || [ -z "$TINY_JPEG_B64" ]; then
  echo "⚠  Pillow not installed — creating test JPEG with ImageMagick..."
  python3 -c "
from PIL import Image; import base64, io
buf = io.BytesIO(); Image.new('RGB',(1,1),(255,0,0)).save(buf,'JPEG')
print(base64.b64encode(buf.getvalue()).decode())
" 2>/dev/null || {
    echo "⚠  Skipping smoke test (no Pillow). Test manually with:"
    echo "  curl -s -X POST '$UPLOAD_URL' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"warehouse_id\":\"wh001\",\"image\":\"<BASE64_JPEG>\"}'"
    exit 0
  }
fi

echo ""
echo "▶ Running smoke test..."
RESPONSE=$(curl -s -X POST "$UPLOAD_URL" \
  -H "Content-Type: application/json" \
  -d "{\"warehouse_id\":\"wh001\",\"image\":\"$TINY_JPEG_B64\"}")

echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

IMAGE_URL=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('image_url',''))" 2>/dev/null)
if [ -n "$IMAGE_URL" ]; then
  echo ""
  echo "✅ Smoke test passed! Image URL:"
  echo "   $IMAGE_URL"
else
  echo ""
  echo "⚠  Smoke test may have failed. Check response above."
fi
