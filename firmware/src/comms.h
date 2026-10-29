#pragma once
#include <Arduino.h>

// Messages from WebSocket and BLE are queued here and handled on the main loop.
// Payloads are either JSON text or binary (first byte = type):
//   0x01 frame:  [fmt][w][h][pixels]   fmt bit0: 0 = RGB565 LE, 1 = RGB332; bit7: mirror
//   0x02 upload: [u32 offset LE][data]
namespace comms {
enum class Src : uint8_t { Ws, Ble };

struct Msg {
  Src src;
  uint32_t client;
  bool binary;
  size_t len;
  uint8_t* data;
};

void begin();
bool push(Src src, uint32_t client, bool binary, const uint8_t* data, size_t len);
bool pop(Msg& m);  // caller frees m.data with free()
void reply(Src src, uint32_t client, const String& json);
void broadcast(const String& json);
}  // namespace comms

namespace net {
void begin();
void loop();
void restartWifi();
void send(uint32_t client, const String& json);
void broadcast(const String& json);
uint8_t clients();
String apIp();
String staIp();
}  // namespace net

namespace ble {
void begin(const char* name);
void stop();
void send(const String& json);
bool connected();
}  // namespace ble
