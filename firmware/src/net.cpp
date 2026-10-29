#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <ESPmDNS.h>
#include <Update.h>
#include <WiFi.h>
#include <map>
#include <vector>
#include "comms.h"
#include "config.h"
#include "settings.h"

namespace net {

static AsyncWebServer server(80);
static AsyncWebSocket ws("/ws");
static std::map<uint32_t, std::vector<uint8_t>> partial;
static bool otaOk = false;
static uint32_t rebootAt = 0;

// No web UI: the phone app talks to /ws (or BLE). Connectivity probes get the
// answers phones expect so they don't pop up a captive sign-in sheet.
static void probeOk(AsyncWebServerRequest* r) {
  r->send(200, "text/html", "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>");
}

static void onWs(AsyncWebSocket*, AsyncWebSocketClient* c, AwsEventType type, void* arg, uint8_t* data, size_t len) {
  if (type == WS_EVT_CONNECT) {
    static const char hello[] = "{\"cmd\":\"get\"}";
    comms::push(comms::Src::Ws, c->id(), false, (const uint8_t*)hello, sizeof(hello) - 1);
    return;
  }
  if (type == WS_EVT_DISCONNECT) {
    partial.erase(c->id());
    return;
  }
  if (type != WS_EVT_DATA) return;
  auto* info = (AwsFrameInfo*)arg;
  bool binary = info->opcode == WS_BINARY || (info->opcode == WS_CONTINUATION && info->message_opcode == WS_BINARY);
  if (info->final && info->index == 0 && info->len == len && info->num == 0) {
    comms::push(comms::Src::Ws, c->id(), binary, data, len);
    return;
  }
  // Fragmented frame or message: collect until the last piece arrives.
  auto& buf = partial[c->id()];
  if (info->index == 0 && info->num == 0) buf.clear();
  if (buf.size() + len > 16384) {
    buf.clear();
    return;
  }
  buf.insert(buf.end(), data, data + len);
  if (info->final && info->index + len == info->len) {
    comms::push(comms::Src::Ws, c->id(), info->message_opcode == WS_BINARY, buf.data(), buf.size());
    buf.clear();
  }
}

void restartWifi() {
  WiFi.disconnect(true);
  WiFi.softAPdisconnect(true);
  WiFi.mode(cfg.staSsid[0] ? WIFI_AP_STA : WIFI_AP);
  WiFi.softAP(cfg.apName, cfg.apPass[0] ? cfg.apPass : nullptr);
  if (cfg.staSsid[0]) WiFi.begin(cfg.staSsid, cfg.staPass);
}

void begin() {
  WiFi.persistent(false);
  WiFi.setSleep(false);
  restartWifi();
  MDNS.begin("proot");
  MDNS.addService("http", "tcp", 80);

  ws.onEvent(onWs);
  server.addHandler(&ws);
  server.on("/hotspot-detect.html", HTTP_GET, probeOk);
  server.on("/library/test/success.html", HTTP_GET, probeOk);
  server.on("/generate_204", HTTP_GET, [](AsyncWebServerRequest* r) { r->send(204); });
  server.on("/", HTTP_GET, [](AsyncWebServerRequest* r) {
    r->send(200, "text/plain", "Proot " PROOT_VERSION " - open the Proot app to control this visor.");
  });

  server.on(
      "/api/ota", HTTP_POST,
      [](AsyncWebServerRequest* r) {
        r->send(otaOk ? 200 : 500, "application/json", otaOk ? "{\"ok\":true}" : "{\"ok\":false}");
        if (otaOk) rebootAt = millis() + 800;
      },
      [](AsyncWebServerRequest*, const String&, size_t index, uint8_t* data, size_t len, bool final) {
        if (index == 0) otaOk = Update.begin(UPDATE_SIZE_UNKNOWN, U_FLASH);
        if (otaOk && Update.write(data, len) != len) otaOk = false;
        if (final && otaOk) otaOk = Update.end(true);
      });
  server.onNotFound([](AsyncWebServerRequest* r) { r->send(404); });
  server.begin();
}

void loop() {
  static uint32_t lastClean = 0;
  if (millis() - lastClean > 2000) {
    ws.cleanupClients(3);
    lastClean = millis();
  }
  if (rebootAt && millis() > rebootAt) ESP.restart();
}

void send(uint32_t client, const String& json) {
  AsyncWebSocketClient* c = ws.client(client);
  if (c && c->canSend()) c->text(json);
}

void broadcast(const String& json) {
  if (ws.count() && ws.availableForWriteAll()) ws.textAll(json);
}

uint8_t clients() { return ws.count(); }
String apIp() { return WiFi.softAPIP().toString(); }
String staIp() { return WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : String(); }

}  // namespace net
