#pragma once
#include <Arduino.h>

#define PROOT_VERSION "1.0.0"

// ProtoFrenz controller V4 pin map (recovered from the v3.0.13 board table).
namespace pins {
constexpr int8_t HUB_R1 = 25, HUB_G1 = 26, HUB_B1 = 27;
constexpr int8_t HUB_R2 = 14, HUB_G2 = 12, HUB_B2 = 13;
constexpr int8_t HUB_A = 23, HUB_B = 19, HUB_C = 5, HUB_D = 17, HUB_E = -1;
constexpr int8_t HUB_LAT = 4, HUB_OE = 15, HUB_CLK = 16;
constexpr int8_t CHEEKS = 21;   // NeoPixel connector
constexpr int8_t BOOP = 36;     // TTP223 output, high while touched
constexpr int8_t BUTTON = 39;   // closes to GND, external pull-up
constexpr int8_t MIC = 35;      // MAX9814 analog out
constexpr int8_t FAN = 18;      // 4-pin fan PWM
}  // namespace pins

constexpr int PANEL_W = 64;
constexpr int PANEL_H = 32;
constexpr int VISOR_W = PANEL_W * 2;
constexpr int VISOR_H = PANEL_H;

constexpr int EXPR_COUNT = 8;
constexpr int GRAD_MAX = 6;
constexpr int CHEEK_MAX = 64;

// Face part sizes, in source pixels (drawn at 1.5x on the panel).
constexpr int EYE_W = 16, EYE_H = 8, EYE_BYTES = 16;
constexpr int NOSE_W = 8, NOSE_H = 8, NOSE_BYTES = 8;
constexpr int MOUTH_W = 40, MOUTH_H = 8, MOUTH_BYTES = 40;
