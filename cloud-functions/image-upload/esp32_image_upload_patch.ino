#include <WiFiClientSecure.h>        // HTTPS support
#include "mbedtls/base64.h"          // Base64 encoding (built-in to ESP32)


// ★ ADD this constant in the CONFIGURATION section,
//   next to CLOUD_FUNCTION_URL:

// Cloud Function for image upload (fill in after deployment)
const char* CLOUD_IMAGE_URL = "https://upload-image-n6hvbwpdfq-el.a.run.app";

// Warehouse ID — MUST match the value used in sendSensorData()
const char* WAREHOUSE_ID = "wh001";




void imageCycle() {
  Serial.println("--- Image Capture (Base64 → Cloud) Start ---");

  // ── 1. Capture JPEG frame ─────────────────────────────────────────
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("  Camera capture FAILED.");
    return;
  }
  Serial.printf("  Captured: %d bytes (%dx%d)\n", fb->len, fb->width, fb->height);

  // Reject frames that are too large (safety)
  if (fb->len > 150000) {
    Serial.println("  Frame too large, skipping upload.");
    esp_camera_fb_return(fb);
    return;
  }

  // ── 2. Base64-encode into PSRAM ───────────────────────────────────
  // Base64 output ≈ input × 4/3, plus padding + null terminator
  size_t b64_buf_size = (fb->len * 4 / 3) + 16;
  char *b64_buf = (char *)ps_malloc(b64_buf_size);
  if (!b64_buf) {
    Serial.println("  PSRAM alloc failed for base64 buffer!");
    esp_camera_fb_return(fb);
    return;
  }

  size_t b64_out_len = 0;
  int ret = mbedtls_base64_encode(
    (unsigned char *)b64_buf, b64_buf_size, &b64_out_len,
    fb->buf, fb->len
  );

  // Done with camera frame buffer — release immediately
  esp_camera_fb_return(fb);

  if (ret != 0) {
    Serial.printf("  Base64 encode failed (err %d)\n", ret);
    free(b64_buf);
    return;
  }
  b64_buf[b64_out_len] = '\0';  // Null-terminate
  Serial.printf("  Base64 encoded: %d chars\n", (int)b64_out_len);

  // ── 3. Check WiFi ─────────────────────────────────────────────────
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("  WiFi not connected. Image not uploaded.");
    free(b64_buf);
    return;
  }

  
  WiFiClientSecure client;
  client.setInsecure();  // Skip TLS cert verification
  client.setTimeout(20);  // 20 second timeout

  HTTPClient http;
  http.begin(client, CLOUD_IMAGE_URL);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(20000);  // 20s total timeout

  // Build the JSON payload in a String
  String payload;
  payload.reserve(b64_out_len + 80);  // Pre-allocate to avoid reallocs
  payload = "{\"warehouse_id\":\"";
  payload += WAREHOUSE_ID;
  payload += "\",\"image\":\"";
  payload += b64_buf;
  payload += "\"}";

  // Free base64 buffer before the HTTP call (HTTP client copies the data)
  free(b64_buf);
  b64_buf = NULL;

  Serial.printf("  Uploading %d bytes to Cloud Function...\n", payload.length());
  int code = http.POST(payload);

  // Release the String memory
  payload = "";

  if (code == 200) {
    String response = http.getString();
    Serial.println("  Image uploaded to cloud!");
    Serial.println("  Response: " + response);
  } else if (code > 0) {
    Serial.printf("  Upload returned HTTP %d\n", code);
    Serial.println("  Body: " + http.getString());
  } else {
    Serial.printf("  Upload failed: %s\n", http.errorToString(code).c_str());
  }

  http.end();
  Serial.println("--- Image Capture End ---\n");
}
