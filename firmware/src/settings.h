#pragma once
#include <ArduinoJson.h>
#include "config.h"

enum class GradMode : uint8_t { Scroll, Vertical, Rainbow, Solid };
enum class CheekMode : uint8_t { Off, Face, Solid, Rainbow, Mic };

struct Expression {
  char name[16];
  uint8_t eye, nose, mouth;
  uint8_t gradCount;
  uint32_t grad[GRAD_MAX];
  float gradSpeed;   // scroll cycles per 10 s
  GradMode gradMode;
  bool blink, talk, cycle, custom;
  char anim[32];     // optional /anim file shown instead of the face
};

struct CustomParts {
  uint8_t eye[EYE_BYTES];
  uint8_t nose[NOSE_BYTES];
  uint8_t mouth[MOUTH_BYTES];
};

struct Settings {
  uint8_t brightness;
  uint8_t fan;
  uint8_t micSens;      // 1..10
  bool boopOn;
  uint8_t boopExpr;
  uint16_t boopMs;
  uint8_t cheekCount;
  CheekMode cheekMode;
  uint8_t cheekBright;
  uint32_t cheekColor;
  bool mirror, swapPanels, rotate;
  uint8_t driver;
  char devName[32];
  char apName[32];
  char apPass[64];
  char staSsid[33];
  char staPass[64];
  bool bleOn;
  uint8_t active;
  Expression expr[EXPR_COUNT];
};

struct Stats {
  uint32_t boops, boots, minutes, peakRapid;
  uint16_t hiscore[4];
};

// Per-pixel paint for a custom part: RGB per cell plus a "painted" bitmask.
struct Paint {
  bool eyeOn, mouthOn;
  uint8_t eye[EYE_W * EYE_H * 3 + EYE_W * EYE_H / 8];
  uint8_t mouth[MOUTH_W * MOUTH_H * 3 + MOUTH_W * MOUTH_H / 8];
};

extern Settings cfg;
extern Stats stats;
extern CustomParts custom[EXPR_COUNT];
extern Paint activePaint;  // paint for cfg.active, reloaded on change

namespace settings {
void load();
void save();          // debounced: writes a few seconds after the last change
void saveNow();
void saveStats();
void loop();
void resetDefaults();
void loadPaint(uint8_t expr);
void savePaint(uint8_t expr, bool eye, const uint8_t* data, size_t len);
void clearPaint(uint8_t expr);
void toJson(JsonObject o);
void exprToJson(const Expression& e, uint8_t i, JsonObject o);
bool apply(const char* key, JsonVariantConst v);  // returns true if known
void applyExpr(uint8_t i, JsonObjectConst o);
}  // namespace settings

uint32_t parseColor(JsonVariantConst v, uint32_t fallback);
void colorHex(uint32_t c, char* out);  // "#rrggbb"
