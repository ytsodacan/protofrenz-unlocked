#pragma once
#include <ArduinoJson.h>
#include "display.h"

// .pfa animation: "PFA1", u16 width, u16 height, u16 frames, u8 flags, u8 0,
// then per frame: u16 delay_ms + width*height RGB565 (little endian).
// width is 64 (one panel; flag bit0 = mirror instead of duplicate) or 128.
namespace anim {
constexpr uint8_t FLAG_MIRROR = 1;

bool begin();  // mount the filesystem
void list(JsonArray out);
bool remove(const char* name);
void fsInfo(JsonObject out);

bool play(const char* name);
void stop();
bool playing();
const char* current();
Layout draw(Canvas& c);  // advances by wall-clock; returns how to present

// Chunked upload, used by WebSocket and BLE alike.
bool uploadBegin(const char* name, uint32_t size);
bool uploadChunk(uint32_t offset, const uint8_t* data, size_t len);
bool uploadEnd();
uint32_t uploadReceived();
}  // namespace anim
