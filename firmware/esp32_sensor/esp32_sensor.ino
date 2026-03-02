#include <WiFi.h>
#include <HTTPClient.h>


const char* WIFI_SSID     = "......";
const char* WIFI_PASSWORD = "........";

const char* SERVER_IP   = "10.43.65.24";  
const int   SERVER_PORT = 5000;

unsigned long lastSend = 0;
#define SEND_INTERVAL 10000

/
int selectedCommodity = 0;

struct Commodity {
  const char* name;
  float temp_min;
  float temp_max;
  float rh_min;
  float rh_max;
};

Commodity commodities[] = {
  { "tomato",  12.0, 15.0, 85.0, 95.0 },
  { "potato",   4.0,  5.0, 95.0, 98.0 },
  { "banana",  13.0, 14.0, 90.0, 95.0 },
  { "rice",    15.0, 20.0, 50.0, 65.0 },
  { "onion",    0.0,  2.0, 65.0, 70.0 }
};

float randomFloat(float minVal, float maxVal) {
  return minVal + (float)random(0, 10001) / 10000.0 * (maxVal - minVal);
}

void setup() {
  Serial.begin(115200);
  Serial.println("\n================================");
  Serial.println("PostHarvest - Flask Mode");
  Serial.println("================================");

  randomSeed(analogRead(0) + millis());

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.println("WiFi Connected: " + WiFi.localIP().toString());

  String url = "http://" + String(SERVER_IP) + ":" + String(SERVER_PORT) + "/data";
  Serial.println("Server: " + url);
  Serial.println("================================\n");
}

void loop() {
  if (millis() - lastSend >= SEND_INTERVAL) {
    lastSend = millis();
    sendData();
  }
}

void sendData() {
  Commodity c = commodities[selectedCommodity];

  float temperature = randomFloat(c.temp_min, c.temp_max);
  float humidity    = randomFloat(c.rh_min, c.rh_max);
  float gasLevel    = randomFloat(5.0, 40.0);

  // 20% chance abnormal values
  if (random(0, 100) < 20) {
    int alertType = random(0, 3);
    switch (alertType) {
      case 0:
        temperature = randomFloat(c.temp_max + 3, c.temp_max + 12);
        Serial.println(">>> SIM: Temp HIGH <<<");
        break;
      case 1:
        humidity = randomFloat(c.rh_min - 30, c.rh_min - 5);
        Serial.println(">>> SIM: Humidity LOW <<<");
        break;
      case 2:
        gasLevel = randomFloat(55.0, 90.0);
        Serial.println(">>> SIM: Gas SPIKE <<<");
        break;
    }
  }

  Serial.printf("[%s] T:%.1f  H:%.1f  G:%.1f\n",
                c.name, temperature, humidity, gasLevel);

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost! Reconnecting...");
    WiFi.reconnect();
    delay(3000);
    return;
  }

  String url = "http://" + String(SERVER_IP) + ":" + String(SERVER_PORT) + "/data";

  /
  String json = "{";
  json += "\"device_id\":\"esp32-node-01\",";
  json += "\"warehouse_id\":\"wh001\",";
  json += "\"commodity\":\"" + String(c.name) + "\",";
  json += "\"temperature\":" + String(temperature, 1) + ",";
  json += "\"humidity\":" + String(humidity, 1) + ",";
  json += "\"gas_level\":" + String(gasLevel, 1);
  json += "}";

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(5000);

  int httpCode = http.POST(json);

  if (httpCode == 200) {
    String response = http.getString();
    Serial.println("OK -> " + response);
  } else if (httpCode < 0) {
    Serial.println("FAIL -> Cannot reach server!");
    Serial.println("Check: Same WiFi? Correct IP? Server running?");
  } else {
    Serial.printf("FAIL -> HTTP %d\n", httpCode);
    Serial.println(http.getString());
  }

  http.end();
  Serial.println("---");
}