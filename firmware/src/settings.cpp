#include "settings.h"
#include <Preferences.h>
#include <WiFi.h>

Settings cfg;
Stats stats;
CustomParts custom[EXPR_COUNT];
Paint activePaint;

static Preferences prefs;
static constexpr uint32_t CFG_VERSION = 3;
static uint32_t dirtyAt = 0;

static void setStr(char* dst, size_t n, const char* src) {
  strncpy(dst, src ? src : "", n - 1);
  dst[n - 1] = 0;
}

static void defaultExpr(Expression& e, const char* name, uint8_t eye, uint8_t nose, uint8_t mouth,
                        std::initializer_list<uint32_t> colors) {
  memset(&e, 0, sizeof(e));
  setStr(e.name, sizeof(e.name), name);
  e.eye = eye;
  e.nose = nose;
  e.mouth = mouth;
  for (uint32_t c : colors) e.grad[e.gradCount++] = c;
  e.gradSpeed = 2.0f;
  e.gradMode = GradMode::Scroll;
  e.blink = true;
  e.talk = true;
  e.cycle = true;
}

void settings::resetDefaults() {
  memset(&cfg, 0, sizeof(cfg));
  cfg.brightness = 110;
  cfg.fan = 191;
  cfg.micSens = 5;
  cfg.boopOn = true;
  cfg.boopExpr = 1;
  cfg.boopMs = 2500;
  cfg.cheekCount = 0;
  cfg.cheekMode = CheekMode::Face;
  cfg.cheekBright = 60;
  cfg.cheekColor = 0xFF3FA4;
  cfg.mirror = true;
  cfg.driver = 0;
  cfg.bleOn = true;
  uint8_t mac[6];
  WiFi.macAddress(mac);
  snprintf(cfg.devName, sizeof(cfg.devName), "Proot-%02X%02X", mac[4], mac[5]);
  setStr(cfg.apName, sizeof(cfg.apName), cfg.devName);

  // Indices refer to the default face set (faces_default.h).
  defaultExpr(cfg.expr[0], "Idle", 0, 0, 0, {0x00E5FF, 0x7A5CFF, 0xFF3FA4});
  defaultExpr(cfg.expr[1], "Happy", 2, 0, 2, {0xFFD23F, 0xFF7A3F, 0xFF3FA4});
  defaultExpr(cfg.expr[2], "Angry", 3, 0, 1, {0xFF1E1E, 0xFF6A00});
  defaultExpr(cfg.expr[3], "Sad", 4, 0, 5, {0x3F7BFF, 0x00C2FF});
  defaultExpr(cfg.expr[4], "Surprised", 5, 3, 7, {0x00FFC8, 0x00A2FF});
  defaultExpr(cfg.expr[5], "Love", 6, 2, 2, {0xFF4FD8, 0xFF2A6D});
  defaultExpr(cfg.expr[6], "Dizzy", 11, 0, 10, {0xB04FFF, 0x00E5FF});
  cfg.expr[6].gradMode = GradMode::Rainbow;
  defaultExpr(cfg.expr[7], "Dead", 7, 5, 4, {0x8A8A9A, 0x50506A});
  cfg.expr[7].blink = false;
  memset(custom, 0, sizeof(custom));
  memset(&stats, 0, sizeof(stats));
}

// One-time import of the stock ProtoFrenz firmware's saved settings.
static bool migrateProtoFrenz() {
  Preferences old;
  if (!old.begin("protofrenz", true)) return false;
  if (!old.isKey("pfe0_e") && !old.isKey("proto_name")) {
    old.end();
    return false;
  }
  for (int i = 0; i < EXPR_COUNT; i++) {
    Expression& e = cfg.expr[i];
    char k[16];
    snprintf(k, sizeof(k), "exn%d", i);
    if (old.isKey(k)) old.getString(k, e.name, sizeof(e.name));
    snprintf(k, sizeof(k), "pfe%d_e", i);
    e.eye = old.getUChar(k, e.eye);
    snprintf(k, sizeof(k), "pfe%d_n", i);
    e.nose = old.getUChar(k, e.nose);
    snprintf(k, sizeof(k), "pfe%d_m", i);
    e.mouth = old.getUChar(k, e.mouth);
    snprintf(k, sizeof(k), "pfe%d_gc", i);
    uint8_t n = old.getUChar(k, 0);
    if (n > 0) {
      e.gradCount = 0;
      for (int j = 0; j < n && j < GRAD_MAX; j++) {
        snprintf(k, sizeof(k), "pfe%dg%d", i, j);
        if (old.isKey(k)) e.grad[e.gradCount++] = old.getUInt(k, 0xFFFFFF);
      }
    }
    snprintf(k, sizeof(k), "pfe%d_gs", i);
    float speed;
    if (old.getBytesLength(k) == 4 && old.getBytes(k, &speed, 4) == 4 && speed > 0 && speed < 20) e.gradSpeed = speed;
    snprintf(k, sizeof(k), "btne%d", i);
    if (old.isKey(k)) e.cycle = old.getUChar(k, 1);
    snprintf(k, sizeof(k), "pfe%d_cb", i);
    e.custom = old.getUChar(k, 0);
    if (e.custom) {
      uint8_t buf[MOUTH_BYTES];
      snprintf(k, sizeof(k), "pfe%d_ce", i);
      if (old.getBytes(k, buf, EYE_BYTES) == EYE_BYTES) memcpy(custom[i].eye, buf, EYE_BYTES);
      snprintf(k, sizeof(k), "pfe%d_cn", i);
      // The stock firmware stores the nose as 2 bytes per row; keep the left byte.
      uint8_t nose16[16];
      if (old.getBytes(k, nose16, 16) == 16)
        for (int r = 0; r < 8; r++) custom[i].nose[r] = nose16[r * 2];
      snprintf(k, sizeof(k), "pfe%d_cm", i);
      if (old.getBytes(k, buf, MOUTH_BYTES) == MOUTH_BYTES) memcpy(custom[i].mouth, buf, MOUTH_BYTES);
      snprintf(k, sizeof(k), "pxh%de", i);
      static uint8_t paint[sizeof(Paint::mouth)];
      size_t len = old.getBytesLength(k);
      if (len == sizeof(Paint::eye) && old.getBytes(k, paint, len) == len) settings::savePaint(i, true, paint, len);
      snprintf(k, sizeof(k), "pxh%dm", i);
      len = old.getBytesLength(k);
      if (len == sizeof(Paint::mouth) && old.getBytes(k, paint, len) == len) settings::savePaint(i, false, paint, len);
    }
  }
  if (old.isKey("fanspeed")) cfg.fan = old.getUChar("fanspeed", cfg.fan);
  if (old.isKey("proto_name")) old.getString("proto_name", cfg.devName, sizeof(cfg.devName));
  if (old.isKey("exan4")) {
    // The old GIF lived in SPIFFS, which Proot reformats; drop the reference.
  }
  old.end();
  return true;
}

void settings::load() {
  prefs.begin("proot", false);
  resetDefaults();
  bool haveCfg = prefs.getUInt("ver", 0) == CFG_VERSION && prefs.getBytesLength("cfg") == sizeof(cfg);
  if (haveCfg) {
    prefs.getBytes("cfg", &cfg, sizeof(cfg));
    prefs.getBytes("cust", custom, sizeof(custom));
  } else if (migrateProtoFrenz()) {
    Serial.println("[cfg] imported settings from ProtoFrenz firmware");
    saveNow();
  }
  if (prefs.getBytesLength("stats") == sizeof(stats)) prefs.getBytes("stats", &stats, sizeof(stats));
  stats.boots++;
  saveStats();
  if (cfg.active >= EXPR_COUNT) cfg.active = 0;
  loadPaint(cfg.active);
}

void settings::save() { dirtyAt = millis() | 1; }

void settings::saveNow() {
  prefs.putUInt("ver", CFG_VERSION);
  prefs.putBytes("cfg", &cfg, sizeof(cfg));
  prefs.putBytes("cust", custom, sizeof(custom));
  dirtyAt = 0;
}

void settings::saveStats() { prefs.putBytes("stats", &stats, sizeof(stats)); }

void settings::loop() {
  if (dirtyAt && millis() - dirtyAt > 3000) saveNow();
  static uint32_t lastMinute = 0;
  if (millis() - lastMinute >= 60000) {
    lastMinute = millis();
    stats.minutes++;
    if (stats.minutes % 10 == 0) saveStats();
  }
}

void settings::loadPaint(uint8_t i) {
  char k[8];
  snprintf(k, sizeof(k), "pe%d", i);
  activePaint.eyeOn = prefs.getBytes(k, activePaint.eye, sizeof(activePaint.eye)) == sizeof(activePaint.eye);
  snprintf(k, sizeof(k), "pm%d", i);
  activePaint.mouthOn =
      prefs.getBytes(k, activePaint.mouth, sizeof(activePaint.mouth)) == sizeof(activePaint.mouth);
}

void settings::savePaint(uint8_t i, bool eye, const uint8_t* data, size_t len) {
  char k[8];
  snprintf(k, sizeof(k), eye ? "pe%d" : "pm%d", i);
  prefs.putBytes(k, data, len);
  if (i == cfg.active) loadPaint(i);
}

void settings::clearPaint(uint8_t i) {
  char k[8];
  snprintf(k, sizeof(k), "pe%d", i);
  prefs.remove(k);
  snprintf(k, sizeof(k), "pm%d", i);
  prefs.remove(k);
  if (i == cfg.active) loadPaint(i);
}

void colorHex(uint32_t c, char* out) { snprintf(out, 8, "#%06X", (unsigned)(c & 0xFFFFFF)); }

uint32_t parseColor(JsonVariantConst v, uint32_t fallback) {
  if (v.is<uint32_t>()) return v.as<uint32_t>() & 0xFFFFFF;
  const char* s = v.as<const char*>();
  if (!s) return fallback;
  if (*s == '#') s++;
  return strtoul(s, nullptr, 16) & 0xFFFFFF;
}

static const char* const GRAD_MODES[] = {"scroll", "vertical", "rainbow", "solid"};
static const char* const CHEEK_MODES[] = {"off", "face", "solid", "rainbow", "mic"};

template <size_t N>
static int indexOf(const char* const (&names)[N], const char* s) {
  for (size_t i = 0; i < N; i++)
    if (s && strcmp(names[i], s) == 0) return i;
  return -1;
}

void settings::exprToJson(const Expression& e, uint8_t i, JsonObject o) {
  o["i"] = i;
  o["name"] = e.name;
  o["eye"] = e.eye;
  o["nose"] = e.nose;
  o["mouth"] = e.mouth;
  JsonArray g = o["colors"].to<JsonArray>();
  char hex[8];
  for (int j = 0; j < e.gradCount; j++) {
    colorHex(e.grad[j], hex);
    g.add(hex);
  }
  o["speed"] = e.gradSpeed;
  o["gradMode"] = GRAD_MODES[(int)e.gradMode];
  o["blink"] = e.blink;
  o["talk"] = e.talk;
  o["cycle"] = e.cycle;
  o["custom"] = e.custom;
  o["anim"] = e.anim;
}

void settings::applyExpr(uint8_t i, JsonObjectConst o) {
  if (i >= EXPR_COUNT) return;
  Expression& e = cfg.expr[i];
  if (o["name"].is<const char*>()) setStr(e.name, sizeof(e.name), o["name"]);
  if (o["eye"].is<int>()) e.eye = o["eye"];
  if (o["nose"].is<int>()) e.nose = o["nose"];
  if (o["mouth"].is<int>()) e.mouth = o["mouth"];
  if (o["colors"].is<JsonArrayConst>()) {
    e.gradCount = 0;
    for (JsonVariantConst c : o["colors"].as<JsonArrayConst>())
      if (e.gradCount < GRAD_MAX) e.grad[e.gradCount++] = parseColor(c, 0xFFFFFF);
    if (!e.gradCount) e.grad[e.gradCount++] = 0xFFFFFF;
  }
  if (o["speed"].is<float>()) e.gradSpeed = constrain(o["speed"].as<float>(), 0.0f, 20.0f);
  int gm = indexOf(GRAD_MODES, o["gradMode"]);
  if (gm >= 0) e.gradMode = (GradMode)gm;
  if (o["blink"].is<bool>()) e.blink = o["blink"];
  if (o["talk"].is<bool>()) e.talk = o["talk"];
  if (o["cycle"].is<bool>()) e.cycle = o["cycle"];
  if (o["custom"].is<bool>()) e.custom = o["custom"];
  if (o["anim"].is<const char*>()) setStr(e.anim, sizeof(e.anim), o["anim"]);
  save();
}

void settings::toJson(JsonObject o) {
  o["brightness"] = cfg.brightness;
  o["fan"] = cfg.fan;
  o["micSens"] = cfg.micSens;
  o["boopOn"] = cfg.boopOn;
  o["boopExpr"] = cfg.boopExpr;
  o["boopMs"] = cfg.boopMs;
  o["cheekCount"] = cfg.cheekCount;
  o["cheekMode"] = CHEEK_MODES[(int)cfg.cheekMode];
  o["cheekBright"] = cfg.cheekBright;
  char hex[8];
  colorHex(cfg.cheekColor, hex);
  o["cheekColor"] = hex;
  o["mirror"] = cfg.mirror;
  o["swapPanels"] = cfg.swapPanels;
  o["rotate"] = cfg.rotate;
  o["driver"] = cfg.driver;
  o["devName"] = cfg.devName;
  o["apName"] = cfg.apName;
  o["apPassSet"] = cfg.apPass[0] != 0;
  o["staSsid"] = cfg.staSsid;
  o["bleOn"] = cfg.bleOn;
}

bool settings::apply(const char* key, JsonVariantConst v) {
  auto u8 = [&](uint8_t& f, int lo, int hi) { f = constrain(v.as<int>(), lo, hi); };
  if (!strcmp(key, "brightness")) u8(cfg.brightness, 0, 255);
  else if (!strcmp(key, "fan")) u8(cfg.fan, 0, 255);
  else if (!strcmp(key, "micSens")) u8(cfg.micSens, 1, 10);
  else if (!strcmp(key, "boopOn")) cfg.boopOn = v.as<bool>();
  else if (!strcmp(key, "boopExpr")) u8(cfg.boopExpr, 0, EXPR_COUNT - 1);
  else if (!strcmp(key, "boopMs")) cfg.boopMs = constrain(v.as<int>(), 300, 20000);
  else if (!strcmp(key, "cheekCount")) u8(cfg.cheekCount, 0, CHEEK_MAX);
  else if (!strcmp(key, "cheekMode")) {
    int m = indexOf(CHEEK_MODES, v.as<const char*>());
    if (m >= 0) cfg.cheekMode = (CheekMode)m;
  } else if (!strcmp(key, "cheekBright")) u8(cfg.cheekBright, 0, 255);
  else if (!strcmp(key, "cheekColor")) cfg.cheekColor = parseColor(v, cfg.cheekColor);
  else if (!strcmp(key, "mirror")) cfg.mirror = v.as<bool>();
  else if (!strcmp(key, "swapPanels")) cfg.swapPanels = v.as<bool>();
  else if (!strcmp(key, "rotate")) cfg.rotate = v.as<bool>();
  else if (!strcmp(key, "driver")) u8(cfg.driver, 0, 3);
  else if (!strcmp(key, "devName")) setStr(cfg.devName, sizeof(cfg.devName), v.as<const char*>());
  else if (!strcmp(key, "apName")) setStr(cfg.apName, sizeof(cfg.apName), v.as<const char*>());
  else if (!strcmp(key, "apPass")) {
    const char* p = v.as<const char*>();
    if (!p || strlen(p) == 0 || strlen(p) >= 8) setStr(cfg.apPass, sizeof(cfg.apPass), p);
  } else if (!strcmp(key, "staSsid")) setStr(cfg.staSsid, sizeof(cfg.staSsid), v.as<const char*>());
  else if (!strcmp(key, "staPass")) setStr(cfg.staPass, sizeof(cfg.staPass), v.as<const char*>());
  else if (!strcmp(key, "bleOn")) cfg.bleOn = v.as<bool>();
  else return false;
  save();
  return true;
}
