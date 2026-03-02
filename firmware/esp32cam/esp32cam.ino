#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include "mbedtls/base64.h"


const char* WIFI_SSID     = "......";
const char* WIFI_PASSWORD = "...........";


const char* CLOUD_IMAGE_URL = ".......................";


const char* WAREHOUSE_ID = "wh001";

#define UPLOAD_INTERVAL 30000  



#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22


#define FLASH_LED_PIN      4



unsigned long lastUpload   = 0;
int           uploadCount  = 0;
bool          cameraReady  = false;



bool setupCamera() {
  camera_config_t config;

  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0       = Y2_GPIO_NUM;
  config.pin_d1       = Y3_GPIO_NUM;
  config.pin_d2       = Y4_GPIO_NUM;
  config.pin_d3       = Y5_GPIO_NUM;
  config.pin_d4       = Y6_GPIO_NUM;
  config.pin_d5       = Y7_GPIO_NUM;
  config.pin_d6       = Y8_GPIO_NUM;
  config.pin_d7       = Y9_GPIO_NUM;
  config.pin_xclk     = XCLK_GPIO_NUM;
  config.pin_pclk     = PCLK_GPIO_NUM;
  config.pin_vsync    = VSYNC_GPIO_NUM;
  config.pin_href     = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn     = PWDN_GPIO_NUM;
  config.pin_reset    = RESET_GPIO_NUM;
  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;

 
  if (psramFound()) {
    Serial.println("PSRAM found! Using higher resolution.");
    config.frame_size   = FRAMESIZE_VGA;      
    config.jpeg_quality = 10;                  
    config.fb_count     = 2;
  } else {
    Serial.println("No PSRAM. Using lower resolution.");
    config.frame_size   = FRAMESIZE_QVGA;     
    config.jpeg_quality = 12;
    config.fb_count     = 1;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init FAILED with error 0x%x\n", err);
    return false;
  }

  // Optional: adjust camera settings
  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    s->set_brightness(s, 1);     
    s->set_contrast(s, 1);       
    s->set_saturation(s, 0);     
    s->set_whitebal(s, 1);       
    s->set_awb_gain(s, 1);       
    s->set_wb_mode(s, 0);        
    s->set_exposure_ctrl(s, 1);  
    s->set_aec2(s, 0);           
    s->set_gain_ctrl(s, 1);      
  }

  Serial.println("Camera initialized successfully!");
  return true;
}



void setupWiFi() {
  Serial.println("\nConnecting to WiFi...");
  Serial.printf("SSID: %s\n", WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi Connected!");
    Serial.printf("   IP Address : %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("   Signal (RSSI): %d dBm\n", WiFi.RSSI());
  } else {
    Serial.println("\n❌ WiFi connection FAILED!");
    Serial.println("   Will retry in loop...");
  }
}



bool ensureWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return true;
  }

  Serial.println("WiFi disconnected. Reconnecting...");
  WiFi.disconnect();
  delay(1000);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi reconnected!");
    return true;
  } else {
    Serial.println("\nWiFi reconnection failed.");
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════
//  FLASH LED CONTROL
// ═══════════════════════════════════════════════════════════════

void flashLED(int times, int duration_ms) {
  pinMode(FLASH_LED_PIN, OUTPUT);
  for (int i = 0; i < times; i++) {
    digitalWrite(FLASH_LED_PIN, HIGH);
    delay(duration_ms);
    digitalWrite(FLASH_LED_PIN, LOW);
    if (i < times - 1) delay(duration_ms);
  }
}

// ═══════════════════════════════════════════════════════════════
//  IMAGE CAPTURE & UPLOAD (Base64 → Cloud Function)
// ═══════════════════════════════════════════════════════════════

void imageCycle() {
  uploadCount++;
  Serial.println("\n╔══════════════════════════════════════╗");
  Serial.printf("║  Image Upload #%d                     ║\n", uploadCount);
  Serial.println("╚══════════════════════════════════════╝");

  // ── 1. Flash LED and Capture JPEG ─────────────────────────────
  Serial.println("  📸 Capturing image...");
  flashLED(1, 100);  // Brief flash

  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println("  ❌ Camera capture FAILED!");
    flashLED(3, 200);  // Error blink
    return;
  }

  Serial.printf("  ✅ Captured: %d bytes (%dx%d)\n", fb->len, fb->width, fb->height);

  // Reject frames that are too large
  if (fb->len > 150000) {
    Serial.println("  ⚠ Frame too large (>150KB), skipping.");
    esp_camera_fb_return(fb);
    return;
  }

  // Reject suspiciously small frames (likely corrupt)
  if (fb->len < 1000) {
    Serial.println("  ⚠ Frame too small (<1KB), likely corrupt. Skipping.");
    esp_camera_fb_return(fb);
    return;
  }

  // ── 2. Base64-encode into PSRAM ───────────────────────────────
  Serial.println("  🔄 Base64 encoding...");

  size_t b64_buf_size = (fb->len * 4 / 3) + 16;
  char *b64_buf = (char *)ps_malloc(b64_buf_size);
  if (!b64_buf) {
    Serial.println("  ❌ PSRAM alloc failed for base64 buffer!");
    esp_camera_fb_return(fb);
    return;
  }

  size_t b64_out_len = 0;
  int ret = mbedtls_base64_encode(
    (unsigned char *)b64_buf, b64_buf_size, &b64_out_len,
    fb->buf, fb->len
  );

  // Release camera buffer immediately
  esp_camera_fb_return(fb);
  fb = NULL;

  if (ret != 0) {
    Serial.printf("  ❌ Base64 encode failed (error %d)\n", ret);
    free(b64_buf);
    return;
  }

  b64_buf[b64_out_len] = '\0';
  Serial.printf("  ✅ Base64 encoded: %d chars\n", (int)b64_out_len);

  // ── 3. Check WiFi ─────────────────────────────────────────────
  if (!ensureWiFi()) {
    Serial.println("  ❌ No WiFi. Image not uploaded.");
    free(b64_buf);
    return;
  }

  // ── 4. Build JSON and POST over HTTPS ─────────────────────────
  Serial.println("  📡 Uploading to Cloud Function...");
  Serial.printf("  URL: %s\n", CLOUD_IMAGE_URL);

  WiFiClientSecure client;
  client.setInsecure();  // Skip TLS cert verification
  client.setTimeout(20); // 20 second timeout

  HTTPClient http;
  http.begin(client, CLOUD_IMAGE_URL);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(20000);

  // Build JSON payload
  // {"warehouse_id":"wh001","image":"<base64_data>"}
  String payload;
  payload.reserve(b64_out_len + 100);
  payload  = "{\"warehouse_id\":\"";
  payload += WAREHOUSE_ID;
  payload += "\",\"image\":\"";
  payload += b64_buf;
  payload += "\"}";

  // Free base64 buffer before HTTP call
  free(b64_buf);
  b64_buf = NULL;

  Serial.printf("  Payload size: %d bytes\n", payload.length());

  // ── 5. Send POST request ──────────────────────────────────────
  unsigned long startTime = millis();
  int httpCode = http.POST(payload);
  unsigned long elapsed = millis() - startTime;

  // Release payload memory
  payload = "";

  // ── 6. Handle response ────────────────────────────────────────
  if (httpCode == 200) {
    String response = http.getString();
    Serial.printf("  ✅ Upload SUCCESS! (%lu ms)\n", elapsed);
    Serial.println("  Response: " + response);
    flashLED(2, 100);  // Success blink
  } else if (httpCode > 0) {
    Serial.printf("  ⚠ HTTP %d (%lu ms)\n", httpCode, elapsed);
    String body = http.getString();
    Serial.println("  Body: " + body);
    flashLED(3, 150);  // Warning blink
  } else {
    Serial.printf("  ❌ Upload FAILED: %s (%lu ms)\n",
                  http.errorToString(httpCode).c_str(), elapsed);
    flashLED(5, 100);  // Error blink
  }

  http.end();

  // ── 7. Print memory stats ─────────────────────────────────────
  Serial.printf("  Free heap: %d bytes | PSRAM: %d bytes\n",
                ESP.getFreeHeap(), ESP.getFreePsram());
  Serial.println("  ────────────────────────────────────\n");
}

// ═══════════════════════════════════════════════════════════════
//  SETUP
// ═══════════════════════════════════════════════════════════════

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n");
  Serial.println("╔══════════════════════════════════════════╗");
  Serial.println("║   PostHarvest — ESP32-CAM Node           ║");
  Serial.println("║   Direct-to-Cloud Image Upload           ║");
  Serial.println("╚══════════════════════════════════════════╝");

  // Flash LED on boot
  pinMode(FLASH_LED_PIN, OUTPUT);
  digitalWrite(FLASH_LED_PIN, LOW);

  // Print memory info
  Serial.printf("\nFree Heap : %d bytes\n", ESP.getFreeHeap());
  Serial.printf("PSRAM     : %s\n", psramFound() ? "Found" : "NOT Found");
  if (psramFound()) {
    Serial.printf("PSRAM Size: %d bytes\n", ESP.getPsramSize());
    Serial.printf("PSRAM Free: %d bytes\n", ESP.getFreePsram());
  }

  // Setup WiFi
  setupWiFi();

  // Setup Camera
  Serial.println("\nInitializing camera...");
  cameraReady = setupCamera();

  if (cameraReady) {
    flashLED(2, 200);  // Success: 2 blinks
  } else {
    flashLED(5, 200);  // Error: 5 blinks
  }

  // Print config summary
  Serial.println("\n═══════════════════════════════════════");
  Serial.printf("  Warehouse ID  : %s\n", WAREHOUSE_ID);
  Serial.printf("  Upload URL    : %s\n", CLOUD_IMAGE_URL);
  Serial.printf("  Interval      : %d seconds\n", UPLOAD_INTERVAL / 1000);
  Serial.printf("  Camera        : %s\n", cameraReady ? "Ready ✅" : "FAILED ❌");
  Serial.printf("  WiFi          : %s\n",
                WiFi.status() == WL_CONNECTED ? "Connected ✅" : "Not connected ❌");
  Serial.println("═══════════════════════════════════════\n");
  Serial.println("Waiting for first upload cycle...\n");
}

// ═══════════════════════════════════════════════════════════════
//  MAIN LOOP
// ═══════════════════════════════════════════════════════════════

void loop() {
  // Only run if camera is ready
  if (!cameraReady) {
    Serial.println("Camera not ready. Retrying init in 10s...");
    delay(10000);
    cameraReady = setupCamera();
    return;
  }

  // Upload on interval
  if (millis() - lastUpload >= UPLOAD_INTERVAL) {
    lastUpload = millis();
    imageCycle();
  }

  // Small delay to prevent watchdog issues
  delay(100);
}