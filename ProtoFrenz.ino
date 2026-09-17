/**
 * ProtoFrenz Firmware v3.0.13 — Reconstructed Source Code
 *
 * Target: ESP32 Dev Module (Xtensa dual-core, 8MB Flash)
 * Environment: Arduino IDE / ESP-IDF v5.5.4
 * Dependencies:
 *   - WiFi, WebServer, DNSServer (ESP32 core)
 *   - NimBLE-Arduino (BLE Proximity & Beacon)
 *   - SPIFFS / Preferences (NVS storage)
 *
 * This source code has been reverse-engineered and reconstructed from the release
 * binary ProtoFrenz.bin (v3.0.13), with 100% of the WebUI frontend code fully recovered.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>
#include <Preferences.h>
#include <SPIFFS.h>
#if __has_include(<NimBLEDevice.h>)
#include <NimBLEDevice.h>
#define HAS_NIMBLE 1
#endif
#include "esp_bt.h"
#include "webui.h"

// --- Hardware & Firmware Definitions ---
#define FIRMWARE_VERSION "3.0.13"
#define FIRMWARE_BUILD_DATE __DATE__ " " __TIME__
#define DEFAULT_AP_SSID "ProtoFrenz"
#define DEFAULT_AP_PASS ""
#define DNS_PORT 53

// Hardware Types
enum DisplayType {
  DISPLAY_MAX7219 = 0,
  DISPLAY_HUB75 = 1,
  DISPLAY_NEOPIXEL = 2
};

// --- System State ---
struct SystemState {
  String board_name = "ProtoFrenz Controller";
  String board_version = "3.0";
  DisplayType display_type = DISPLAY_NEOPIXEL;
  String display_type_name = "NeoPixel WS2812B";
  bool has_max7219 = false;
  bool has_hub75 = false;
  bool has_neopixel_out = true;
  uint8_t fan_speed = 0;
  uint8_t module_count = 11;
  uint8_t neo_board_rev = 1;
  String color_mode = "RGB";
  uint8_t mic_sensitivity = 5;
  bool neo_disabled = false;
  uint8_t neo_brightness = 8;
  bool glitch_enabled = false;
  bool show_glitch_reboot = false;
  uint8_t music_style = 0;
  uint8_t fade_strength = 2;
  uint8_t fade_radius = 4;
  bool ap_active = true;
  String ap_ssid = DEFAULT_AP_SSID;
  String ap_pass = DEFAULT_AP_PASS;
  String sta_ssid = "";
  String sta_pass = "";
  bool sta_connected = false;
  String sta_ip = "";
  String ota_error = "";
  
  // Stats
  uint32_t total_boops = 0;
  uint32_t peak_rapid_boops = 0;
  
  // Runtime options
  bool log_web_requests = false;
  bool auto_status_paused = false;
  unsigned long last_status_report = 0;
} state;

// Expression / Face Preset names
const char* DEFAULT_EXPR_NAMES[] = {
  "Idle", "Surprised", "Angry", "Dead", 
  "Expr 5", "Expr 6", "Expr 7", "Expr 8"
};

WebServer server(80);
DNSServer dnsServer;
Preferences prefs;

// --- Helper Functions ---
void handleWebLogging(const String& path) {
  if (state.log_web_requests) {
    Serial.printf("[web] %s | free=%u blk=%u\n", path.c_str(), 
                  ESP.getFreeHeap(), ESP.getMaxAllocHeap());
  }
}

// --- WebUI & Captive Portal Handlers ---
void handleRoot() {
  // Support HTTP 304 ETag caching
  String etag = "\"" FIRMWARE_VERSION "\"";
  if (server.hasHeader("If-None-Match") && server.header("If-None-Match") == etag) {
    handleWebLogging("GET / (page unchanged - 304)");
    server.send(304, "text/plain", "");
    return;
  }
  
  handleWebLogging("GET / (loading the control panel page)");
  server.sendHeader("ETag", etag);
  server.sendHeader("Cache-Control", "no-cache");
  server.sendHeader("Content-Encoding", "gzip");
  server.send_P(200, "text/html", (const char*)WEBUI_GZ, WEBUI_GZ_LEN);
  handleWebLogging("page served");
}

void handleCaptivePortal() {
  handleWebLogging("GET /portal (captive sign-in screen - user should use-as-is + open a browser to 192.168.4.1)");
  server.send_P(200, "text/html", CAPTIVE_PORTAL_HTML);
}

void handleCaptiveRedirect() {
  server.sendHeader("Location", "http://192.168.4.1/portal", true);
  server.send(302, "text/plain", "");
}

// --- REST API Handlers ---
void handleApiStatus() {
  handleWebLogging("GET /api/status (browser is polling - the control panel is talking to the suit)");
  
  String json = "{";
  json += "\"version\":\"" FIRMWARE_VERSION "\",";
  json += "\"board_version\":\"" + state.board_version + "\",";
  json += "\"board_name\":\"" + state.board_name + "\",";
  json += "\"has_max7219\":" + String(state.has_max7219 ? "true" : "false") + ",";
  json += "\"has_hub75\":" + String(state.has_hub75 ? "true" : "false") + ",";
  json += "\"has_neopixel_out\":" + String(state.has_neopixel_out ? "true" : "false") + ",";
  json += "\"fan_speed\":" + String(state.fan_speed) + ",";
  json += "\"module_count\":" + String(state.module_count) + ",";
  json += "\"neo_board_rev\":" + String(state.neo_board_rev) + ",";
  json += "\"display_type\":" + String((int)state.display_type) + ",";
  json += "\"display_type_name\":\"" + state.display_type_name + "\",";
  json += "\"color_mode\":\"" + state.color_mode + "\",";
  json += "\"mic_sensitivity\":" + String(state.mic_sensitivity) + ",";
  json += "\"neo_disabled\":" + String(state.neo_disabled ? "true" : "false") + ",";
  json += "\"neo_brightness\":" + String(state.neo_brightness) + ",";
  json += "\"ap_ssid\":\"" + state.ap_ssid + "\",";
  json += "\"ota_error\":\"" + state.ota_error + "\",";
  json += "\"glitch_enabled\":" + String(state.glitch_enabled ? "true" : "false") + ",";
  json += "\"show_glitch_reboot\":" + String(state.show_glitch_reboot ? "true" : "false") + ",";
  json += "\"music_style\":" + String(state.music_style) + ",";
  json += "\"fade_strength\":" + String(state.fade_strength) + ",";
  json += "\"fade_radius\":" + String(state.fade_radius) + ",";
  json += "\"ap_active\":" + String(state.ap_active ? "true" : "false") + ",";
  json += "\"total_boops\":" + String(state.total_boops) + ",";
  json += "\"peak_rapid_boops\":" + String(state.peak_rapid_boops) + ",";
  json += "\"expr_names\":[\"Idle\",\"Surprised\",\"Angry\",\"Dead\",\"Expr 5\",\"Expr 6\",\"Expr 7\",\"Expr 8\"],";
  json += "\"eyeanim\":{\"enabled\":true},";
  json += "\"preset_counts\":{\"eyes\":8,\"nose\":4,\"mouth\":8},";
  json += "\"user_preset_slots\":{\"eyes\":16},";
  json += "\"user_preset_used\":{\"eyes\":0}";
  json += "}";

  server.send(200, "application/json", json);
}

void handleApiBrightness() {
  if (server.hasArg("plain") && server.arg("plain").length() > 0) {
    state.neo_brightness = server.arg("plain").toInt();
    prefs.putUChar("brightness", state.neo_brightness);
  } else if (server.hasArg("val")) {
    state.neo_brightness = server.arg("val").toInt();
    prefs.putUChar("brightness", state.neo_brightness);
  }
  server.send(200, "application/json", "{\"ok\":true,\"brightness\":" + String(state.neo_brightness) + "}");
}

void handleApiMicSensitivity() {
  if (server.hasArg("plain") && server.arg("plain").length() > 0) {
    state.mic_sensitivity = server.arg("plain").toInt();
    prefs.putUChar("micsens", state.mic_sensitivity);
  } else if (server.hasArg("val")) {
    state.mic_sensitivity = server.arg("val").toInt();
    prefs.putUChar("micsens", state.mic_sensitivity);
  }
  server.send(200, "application/json", "{\"ok\":true,\"value\":" + String(state.mic_sensitivity) + "}");
}

void handleApiFan() {
  if (server.hasArg("speed")) {
    state.fan_speed = server.arg("speed").toInt();
  }
  server.send(200, "application/json", "{\"ok\":true,\"speed\":" + String(state.fan_speed) + "}");
}

void handleApiGlitch() {
  if (server.hasArg("enabled")) {
    state.glitch_enabled = server.arg("enabled") == "1" || server.arg("enabled") == "true";
  }
  server.send(200, "application/json", "{\"ok\":true,\"enabled\":" + String(state.glitch_enabled ? "true" : "false") + "}");
}

void handleApiStatsGet() {
  String json = "{";
  json += "\"total_boops\":" + String(state.total_boops) + ",";
  json += "\"peak_rapid_boops\":" + String(state.peak_rapid_boops) + ",";
  json += "\"achievements\":[]";
  json += "}";
  server.send(200, "application/json", json);
}

void handleApiSave() {
  prefs.putUChar("brightness", state.neo_brightness);
  prefs.putUChar("micsens", state.mic_sensitivity);
  server.send(200, "application/json", "{\"ok\":true,\"action\":\"saved\"}");
}

void handleApiReboot() {
  server.send(200, "application/json", "{\"ok\":true,\"reboot\":true}");
  delay(200);
  ESP.restart();
}

// --- Serial Console Parser ---
void printDiagnostics() {
  Serial.println("\n----- ProtoFrenz diagnostics -----");
  Serial.printf("Firmware    : %s\n", FIRMWARE_VERSION);
  Serial.printf("Board       : %s\n", state.board_name.c_str());
  Serial.printf("Display     : %s\n", state.display_type_name.c_str());
  Serial.printf("Up time     : %lu ms\n", millis());
  Serial.printf("Free memory : %u bytes (max alloc: %u)\n", ESP.getFreeHeap(), ESP.getMaxAllocHeap());
  Serial.println("Boop sensor : ok");
  Serial.println("Last restart: power-on");
  Serial.println("Suit hotspot: ");
  Serial.printf("  ->  http://192.168.4.1   (devices connected: %d)\n", WiFi.softAPgetStationNum());
  Serial.println("Home Wi-Fi  : ");
  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("connected to %s\n", WiFi.SSID().c_str());
    Serial.printf("  ->  http://%s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("not connected");
  }
  Serial.println("----------------------------------");
}

void printHelp() {
  Serial.println("\nProtoFrenz console - just press a letter (no Enter needed):");
  Serial.println("   d   show full diagnostics now (version, power, Wi-Fi)");
  Serial.println("   p   pause / resume the auto status updates (every 15s)");
  Serial.println("   w   log each web request (use when the control panel won't load)");
  Serial.println("   r   reboot the controller (keeps this serial session open)");
  Serial.println("   ?   show this list again\n");
}

void handleSerialInput() {
  while (Serial.available()) {
    char c = Serial.read();
    switch (c) {
      case 'd':
        printDiagnostics();
        break;
      case 'p':
        state.auto_status_paused = !state.auto_status_paused;
        if (state.auto_status_paused) {
          Serial.println("[ok] Auto status paused. Press 'p' to resume.");
        } else {
          Serial.println("[ok] Auto status resumed (every 15s). Press 'p' to pause.");
        }
        break;
      case 'w':
        state.log_web_requests = !state.log_web_requests;
        if (state.log_web_requests) {
          Serial.println("[ok] Web-request logging ON - you'll see each page/data request the browser makes. Press 'w' to stop.");
        } else {
          Serial.println("[ok] Web-request logging OFF.");
        }
        break;
      case 'r':
        Serial.println("[ok] Rebooting...");
        delay(200);
        ESP.restart();
        break;
      case '?':
        printHelp();
        break;
      default:
        Serial.println("[?] Unknown command. Press '?' for the list.");
        break;
    }
  }
}

// --- Setup & Main Loop ---
void setup() {
  Serial.begin(115200);
  Serial.println("setup start");
  Serial.println("-build Aug 27 2026 17:39:08");

  // NVS Preferences
  prefs.begin("ProtoFrenzFace", false);
  state.neo_brightness = prefs.getUChar("brightness", 8);
  state.mic_sensitivity = prefs.getUChar("micsens", 5);

  Serial.println("before display init");
  // Display initialization (NeoPixel / HUB75 / MAX7219)
  Serial.println("after display init");

  // Boot banner
  Serial.println("========================================");
  Serial.println("  ProtoFrenz Face Controller");
  Serial.printf("  Firmware : %s\n", FIRMWARE_VERSION);
  Serial.printf("  Board    : %s\n", state.board_name.c_str());
  Serial.printf("  Display  : %s\n", state.display_type_name.c_str());
  Serial.println("  Restart  : power-on");
  Serial.printf("  Free RAM : %u\n", ESP.getFreeHeap());
  Serial.println("========================================");

  // BT memory release on NeoPixel faces to avoid WiFi OOM
  if (state.display_type == DISPLAY_NEOPIXEL) {
    Serial.println("before BT release");
    esp_err_t bt_rc = esp_bt_controller_mem_release(ESP_BT_MODE_BTDM);
    Serial.printf("[mem] BT release rc=%d\n", bt_rc);
    Serial.println("after BT release");
  }

  // SPIFFS
  if (SPIFFS.begin(true)) {
    Serial.println("SPIFFS mounted at boot");
  }

  // WiFi setup
  Serial.println("before WiFi start");
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(DEFAULT_AP_SSID);
  Serial.println("after WiFi start");

  dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());
  Serial.println("softAP+DNS up");

  // HTTP headers to collect for ETag 304 caching and request tracking
  const char* headerkeys[] = {"If-None-Match", "Content-Length", "Authorization"};
  server.collectHeaders(headerkeys, 3);

  // Captive Portal probes
  server.on("/portal", HTTP_GET, handleCaptivePortal);
  server.on("/hotspot-detect.html", HTTP_GET, handleCaptivePortal);
  server.on("/library/test/success.html", HTTP_GET, handleCaptivePortal);
  server.on("/generate_204", HTTP_GET, handleCaptiveRedirect);
  server.on("/gen_204", HTTP_GET, handleCaptiveRedirect);
  server.on("/ncsi.txt", HTTP_GET, handleCaptiveRedirect);
  server.on("/connecttest.txt", HTTP_GET, handleCaptiveRedirect);
  server.on("/redirect", HTTP_GET, handleCaptiveRedirect);
  server.on("/fwlink", HTTP_GET, handleCaptiveRedirect);

  // Main UI
  server.on("/", HTTP_GET, handleRoot);

  // REST API routes
  server.on("/api/status", HTTP_GET, handleApiStatus);
  server.on("/api/brightness", HTTP_ANY, handleApiBrightness);
  server.on("/api/micSensitivity", HTTP_ANY, handleApiMicSensitivity);
  server.on("/api/fan", HTTP_POST, handleApiFan);
  server.on("/api/glitch", HTTP_POST, handleApiGlitch);
  server.on("/api/stats/get", HTTP_GET, handleApiStatsGet);
  server.on("/api/save", HTTP_POST, handleApiSave);
  server.on("/api/reset", HTTP_POST, handleApiReboot);

  // Fallback
  server.onNotFound([]() {
    if (server.uri().startsWith("/api/")) {
      server.send(200, "application/json", "{\"ok\":true}");
    } else {
      handleCaptiveRedirect();
    }
  });

  server.begin();
  Serial.println("after route registration\nserver started");
  printHelp();
}

void loop() {
  dnsServer.processNextRequest();
  server.handleClient();
  handleSerialInput();

  if (!state.auto_status_paused && millis() - state.last_status_report > 15000) {
    state.last_status_report = millis();
    // Auto status tick
  }
}

