#pragma once
#include "display.h"

namespace io {
enum class Button : uint8_t { None, Short, Long };

void begin();
void loop();
bool booped();             // edge since last call
Button button();           // event since last call
bool buttonHeld();
float micLevel();          // smoothed 0..1
uint16_t micRaw();         // last peak-to-peak, for the settings meter
uint8_t rapidBoops();      // boops in the last 5 s

void setFan(uint8_t duty);
void cheeks(const RGB* colors, uint8_t n, uint8_t brightness);
void cheeksBegin(uint8_t count);
}  // namespace io
