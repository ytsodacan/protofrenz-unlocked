// Proot — open firmware for the ProtoFrenz HUB75 controller.
#include <Arduino.h>
#include <ArduinoJson.h>
#include <WiFi.h>
#include "anim.h"
#include "comms.h"
#include "config.h"
#include "display.h"
#include "faces.h"
#include "games.h"
#include "io.h"
#include "settings.h"

enum class Mode : uint8_t { Face, Anim, Text, Game, Draw, Test };
static const char* const MODE_NAMES[] = {"face", "anim", "text", "game", "draw", "test"};

static Canvas canvas;
static Mode mode = Mode::Face;
static Layout drawLayout = Layout::Mirror;

static uint32_t boopUntil = 0;
static float blinkT = -1;        // seconds into the current blink, <0 when idle
static uint32_t nextBlink = 0;

static String textMsg = "Hello!";
static uint32_t textColor = 0;   // 0 = rainbow
static float textSpeed = 28;
static uint8_t textSize = 2;
static float textX = VISOR_W;

static bool stateDirty = true;
static uint32_t lastState = 0;
static comms::Src meterSrc;
static uint32_t meterClient = 0, meterUntil = 0;

// ------------------------------------------------------------ state messages

static void markDirty() { stateDirty = true; }

static String stateJson() {
  JsonDocument d;
  d["t"] = "state";
  d["version"] = PROOT_VERSION;
  d["vendorFaces"] = faces::vendor();
  d["mode"] = MODE_NAMES[(int)mode];
  d["active"] = cfg.active;
  d["boop"] = millis() < boopUntil;
  JsonArray ex = d["expr"].to<JsonArray>();
  for (int i = 0; i < EXPR_COUNT; i++) settings::exprToJson(cfg.expr[i], i, ex.add<JsonObject>());
  settings::toJson(d["cfg"].to<JsonObject>());
  JsonObject g = d["game"].to<JsonObject>();
  g["id"] = games::slug(games::current());
  g["score"] = games::score();
  JsonArray hs = g["best"].to<JsonArray>();
  for (int i = 0; i < games::COUNT; i++) hs.add(stats.hiscore[i]);
  d["anim"] = anim::current();
  JsonObject tx = d["text"].to<JsonObject>();
  tx["s"] = textMsg;
  char hex[8];
  colorHex(textColor, hex);
  tx["color"] = textColor ? hex : "rainbow";
  tx["speed"] = textSpeed;
  tx["size"] = textSize;
  JsonObject st = d["stats"].to<JsonObject>();
  st["boops"] = stats.boops;
  st["boots"] = stats.boots;
  st["minutes"] = stats.minutes;
  st["peakRapid"] = stats.peakRapid;
  JsonObject n = d["net"].to<JsonObject>();
  n["ap"] = net::apIp();
  n["sta"] = net::staIp();
  n["wsClients"] = net::clients();
  n["ble"] = ble::connected();
  n["heap"] = ESP.getFreeHeap();
  String s;
  serializeJson(d, s);
  return s;
}

static String facesJson() {
  JsonDocument d;
  d["t"] = "faces";
  const char* keys[] = {"eyes", "noses", "mouths"};
  const size_t sizes[] = {EYE_BYTES, NOSE_BYTES, MOUTH_BYTES};
  for (int p = 0; p < 3; p++) {
    JsonArray arr = d[keys[p]].to<JsonArray>();
    uint8_t buf[MOUTH_BYTES];
    char hex[MOUTH_BYTES * 2 + 1];
    for (int i = 0; i < faces::count((faces::Part)p); i++) {
      faces::bits((faces::Part)p, i, buf);
      for (size_t k = 0; k < sizes[p]; k++) sprintf(hex + k * 2, "%02x", buf[k]);
      JsonObject o = arr.add<JsonObject>();
      o["n"] = faces::name((faces::Part)p, i);
      o["b"] = hex;
    }
  }
  JsonArray cu = d["custom"].to<JsonArray>();
  for (int i = 0; i < EXPR_COUNT; i++) {
    JsonObject o = cu.add<JsonObject>();
    char hex[MOUTH_BYTES * 2 + 1];
    auto put = [&](const char* k, const uint8_t* b, size_t n) {
      for (size_t j = 0; j < n; j++) sprintf(hex + j * 2, "%02x", b[j]);
      o[k] = hex;
    };
    put("eye", custom[i].eye, EYE_BYTES);
    put("nose", custom[i].nose, NOSE_BYTES);
    put("mouth", custom[i].mouth, MOUTH_BYTES);
  }
  String s;
  serializeJson(d, s);
  return s;
}

// ------------------------------------------------------------ actions

static void setMode(Mode m) {
  if (m != Mode::Game) games::stop();
  if (m != Mode::Anim && mode == Mode::Anim) anim::stop();
  mode = m;
  canvas.clear();
  markDirty();
}

static void activate(uint8_t i) {
  cfg.active = i % EXPR_COUNT;
  settings::loadPaint(cfg.active);
  const Expression& e = cfg.expr[cfg.active];
  if (e.anim[0] && anim::play(e.anim)) setMode(Mode::Anim);
  else setMode(Mode::Face);
  settings::save();
}

static void nextExpression(int dir) {
  for (int k = 1; k <= EXPR_COUNT; k++) {
    uint8_t i = (cfg.active + EXPR_COUNT + dir * k) % EXPR_COUNT;
    if (cfg.expr[i].cycle) {
      activate(i);
      return;
    }
  }
}

static bool hexToBytes(const char* hex, uint8_t* out, size_t n) {
  if (!hex || strlen(hex) != n * 2) return false;
  for (size_t i = 0; i < n; i++) {
    char b[3] = {hex[i * 2], hex[i * 2 + 1], 0};
    out[i] = strtoul(b, nullptr, 16);
  }
  return true;
}

static void applyHardware() {
  display::setBrightness(cfg.brightness);
  display::setOrientation(cfg.swapPanels, cfg.rotate);
  io::setFan(cfg.fan);
}

// ------------------------------------------------------------ protocol

static void handleBinary(const comms::Msg& m) {
  const uint8_t* p = m.data;
  if (m.len < 1) return;
  if (p[0] == 0x01 && m.len >= 4) {  // live frame
    uint8_t fmt = p[1], w = p[2], h = p[3];
    size_t bpp = (fmt & 1) ? 1 : 2;
    if ((w != PANEL_W && w != VISOR_W) || h != PANEL_H || m.len < 4 + (size_t)w * h * bpp) return;
    if (mode != Mode::Draw) setMode(Mode::Draw);
    const uint8_t* px = p + 4;
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++) {
        size_t i = y * w + x;
        RGB c;
        if (bpp == 1) {
          uint8_t v = px[i];
          c = {uint8_t((v >> 5) * 255 / 7), uint8_t(((v >> 2) & 7) * 255 / 7), uint8_t((v & 3) * 85)};
        } else {
          c = from565(px[i * 2] | (px[i * 2 + 1] << 8));
        }
        canvas.set(x, y, c);
      }
    drawLayout = w == VISOR_W ? Layout::Span : (fmt & 0x80) ? Layout::Mirror : Layout::Duplicate;
  } else if (p[0] == 0x02 && m.len >= 5) {  // upload chunk
    uint32_t off;
    memcpy(&off, p + 1, 4);
    bool ok = anim::uploadChunk(off, p + 5, m.len - 5);
    comms::reply(m.src, m.client,
                 ok ? String("{\"t\":\"up\",\"got\":") + anim::uploadReceived() + "}" : "{\"t\":\"up\",\"err\":\"chunk\"}");
  }
}

static void handleJson(const comms::Msg& m) {
  JsonDocument in;
  if (deserializeJson(in, (const char*)m.data, m.len)) return;
  const char* cmd = in["cmd"] | "";
  JsonDocument out;
  out["t"] = "ack";
  if (!in["id"].isNull()) out["id"] = in["id"];
  out["ok"] = true;
  bool sendAck = !in["id"].isNull();

  if (!strcmp(cmd, "get")) {
    comms::reply(m.src, m.client, stateJson());
    return;
  } else if (!strcmp(cmd, "faces")) {
    comms::reply(m.src, m.client, facesJson());
    return;
  } else if (!strcmp(cmd, "expr")) {
    activate(in["i"] | 0);
  } else if (!strcmp(cmd, "next")) {
    nextExpression(in["dir"] | 1);
  } else if (!strcmp(cmd, "setExpr")) {
    uint8_t i = in["i"] | 0;
    settings::applyExpr(i, in.as<JsonObjectConst>());
    if (i == cfg.active) activate(i);
    markDirty();
  } else if (!strcmp(cmd, "custom")) {
    uint8_t i = in["i"] | 0;
    if (i < EXPR_COUNT) {
      hexToBytes(in["eye"], custom[i].eye, EYE_BYTES);
      hexToBytes(in["nose"], custom[i].nose, NOSE_BYTES);
      hexToBytes(in["mouth"], custom[i].mouth, MOUTH_BYTES);
      if (in["clearPaint"] | false) settings::clearPaint(i);
      cfg.expr[i].custom = true;
      settings::save();
      if (i == cfg.active) activate(i);
      markDirty();
    }
  } else if (!strcmp(cmd, "set")) {
    if (in["v"].is<JsonObject>()) {
      for (JsonPairConst kv : in["v"].as<JsonObjectConst>()) settings::apply(kv.key().c_str(), kv.value());
    } else {
      out["ok"] = settings::apply(in["k"] | "", in["v"]);
    }
    applyHardware();
    if (in["v"]["cheekCount"].is<int>() || !strcmp(in["k"] | "", "cheekCount")) io::cheeksBegin(cfg.cheekCount);
    markDirty();
  } else if (!strcmp(cmd, "mode")) {
    const char* mname = in["m"] | "face";
    for (int i = 0; i < 6; i++)
      if (!strcmp(mname, MODE_NAMES[i])) setMode((Mode)i);
    if (mode == Mode::Face) activate(cfg.active);
  } else if (!strcmp(cmd, "text")) {
    if (in["s"].is<const char*>()) textMsg = in["s"].as<const char*>();
    if (!in["color"].isNull()) textColor = !strcmp(in["color"] | "", "rainbow") ? 0 : parseColor(in["color"], 0xFFFFFF) | 0x010101;
    if (in["speed"].is<float>()) textSpeed = constrain(in["speed"].as<float>(), 4.0f, 120.0f);
    if (in["size"].is<int>()) textSize = constrain(in["size"].as<int>(), 1, 4);
    textX = VISOR_W;
    setMode(Mode::Text);
  } else if (!strcmp(cmd, "anim")) {
    if (anim::play(in["name"] | "")) setMode(Mode::Anim);
    else out["ok"] = false;
  } else if (!strcmp(cmd, "files")) {
    JsonDocument d;
    d["t"] = "files";
    anim::list(d["files"].to<JsonArray>());
    anim::fsInfo(d["fs"].to<JsonObject>());
    String s;
    serializeJson(d, s);
    comms::reply(m.src, m.client, s);
    return;
  } else if (!strcmp(cmd, "rm")) {
    out["ok"] = anim::remove(in["name"] | "");
  } else if (!strcmp(cmd, "upStart")) {
    out["ok"] = anim::uploadBegin(in["name"] | "anim", in["size"] | 0);
    sendAck = true;
  } else if (!strcmp(cmd, "upEnd")) {
    out["ok"] = anim::uploadEnd();
    sendAck = true;
  } else if (!strcmp(cmd, "game")) {
    int g = games::fromSlug(in["g"] | "");
    if (g >= 0) {
      setMode(Mode::Game);
      games::start(g);
    } else {
      activate(cfg.active);
    }
  } else if (!strcmp(cmd, "key")) {
    games::Key k;
    if (games::keyFromName(in["k"] | "", k)) games::key(k, in["d"] | false);
    return;  // keys are fire-and-forget
  } else if (!strcmp(cmd, "meter")) {
    meterSrc = m.src;
    meterClient = m.client;
    meterUntil = (in["on"] | false) ? millis() + 30000 : 0;
    return;
  } else if (!strcmp(cmd, "applyWifi")) {
    settings::saveNow();
    net::restartWifi();
  } else if (!strcmp(cmd, "save")) {
    settings::saveNow();
  } else if (!strcmp(cmd, "reboot")) {
    settings::saveNow();
    comms::reply(m.src, m.client, "{\"t\":\"ack\",\"ok\":true}");
    delay(300);
    ESP.restart();
  } else if (!strcmp(cmd, "factoryReset")) {
    settings::resetDefaults();
    settings::saveNow();
    delay(200);
    ESP.restart();
  } else if (!strcmp(cmd, "resetStats")) {
    memset(&stats, 0, sizeof(stats));
    settings::saveStats();
    markDirty();
  } else {
    out["ok"] = false;
    out["err"] = "unknown cmd";
  }
  if (sendAck) {
    String s;
    serializeJson(out, s);
    comms::reply(m.src, m.client, s);
  }
}

// ------------------------------------------------------------ rendering

static float blinkAmount(float dt) {
  uint32_t now = millis();
  if (blinkT < 0 && now >= nextBlink) blinkT = 0;
  if (blinkT < 0) return 0;
  blinkT += dt;
  const float close = 0.07f, hold = 0.04f, open = 0.11f;
  float v;
  if (blinkT < close) v = blinkT / close;
  else if (blinkT < close + hold) v = 1;
  else if (blinkT < close + hold + open) v = 1 - (blinkT - close - hold) / open;
  else {
    blinkT = -1;
    nextBlink = now + random(2200, 6500);
    if (random(6) == 0) nextBlink = now + 180;  // occasional double blink
    return 0;
  }
  return v;
}

static void renderText(float dt) {
  canvas.clear();
  canvas.setTextWrap(false);
  canvas.setTextSize(textSize);
  int cw = 6 * textSize, w = textMsg.length() * cw;
  int y = (VISOR_H - 8 * textSize) / 2;
  float t = millis() / 1000.0f;
  for (size_t i = 0; i < textMsg.length(); i++) {
    int x = int(textX) + i * cw;
    if (x > VISOR_W || x < -cw) continue;
    RGB c = textColor ? fromHex(textColor) : hsv(i * 0.06f - t * 0.25f, 1, 1);
    canvas.setTextColor(rgb565(c));
    canvas.setCursor(x, y);
    canvas.print(textMsg[i]);
  }
  textX -= textSpeed * dt;
  if (textX < -w) textX = VISOR_W;
}

static void renderTest() {
  canvas.clear();
  float t = millis() / 1000.0f;
  const RGB bars[] = {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {255, 255, 255}};
  for (int p = 0; p < 2; p++) {
    for (int b = 0; b < 4; b++) canvas.fillRect(p * PANEL_W + b * 16, 0, 16, 6, rgb565(bars[b]));
    canvas.setTextSize(1);
    canvas.setTextColor(rgb565({255, 255, 255}));
    canvas.setCursor(p * PANEL_W + 4, 10);
    canvas.print(p == 0 ? "PANEL 1" : "PANEL 2");
    canvas.setCursor(p * PANEL_W + 4, 20);
    canvas.print(p == 0 ? "<- start" : "end ->");
  }
  int x = int(t * 30) % VISOR_W;
  canvas.drawFastVLine(x, 0, VISOR_H, rgb565({255, 200, 0}));
}

static void updateCheeks(float t) {
  if (!cfg.cheekCount || cfg.cheekMode == CheekMode::Off) {
    static bool cleared = false;
    if (!cleared && cfg.cheekCount) {
      RGB off[CHEEK_MAX] = {};
      io::cheeks(off, cfg.cheekCount, 0);
    }
    cleared = true;
    return;
  }
  RGB c[CHEEK_MAX];
  const Expression& e = cfg.expr[millis() < boopUntil ? cfg.boopExpr : cfg.active];
  for (int i = 0; i < cfg.cheekCount; i++) {
    float pos = i / float(cfg.cheekCount);
    switch (cfg.cheekMode) {
      case CheekMode::Face: c[i] = faces::gradientAt(e, pos, t); break;
      case CheekMode::Solid: c[i] = fromHex(cfg.cheekColor); break;
      case CheekMode::Rainbow: c[i] = hsv(pos - t * 0.2f, 1, 1); break;
      default: c[i] = lerp({0, 0, 0}, fromHex(cfg.cheekColor), 0.15f + 0.85f * io::micLevel()); break;
    }
  }
  io::cheeks(c, cfg.cheekCount, cfg.cheekBright);
}

// ------------------------------------------------------------ setup / loop

void setup() {
  Serial.begin(115200);
  settings::load();
  io::begin();
  comms::begin();
  if (!display::begin(cfg.driver)) Serial.println("[display] HUB75 DMA allocation failed");
  applyHardware();
  io::cheeksBegin(cfg.cheekCount);
  if (!anim::begin()) Serial.println("[fs] mount failed");
  randomSeed(esp_random());
  nextBlink = millis() + 1500;
  activate(cfg.active);
  net::begin();
  if (cfg.bleOn) ble::begin(cfg.devName);
  Serial.printf("Proot %s ready  heap=%u  ap=%s\n", PROOT_VERSION, ESP.getFreeHeap(), cfg.apName);
}

void loop() {
  static uint32_t last = millis();
  uint32_t now = millis();
  float dt = (now - last) / 1000.0f;
  last = now;
  float t = now / 1000.0f;

  io::loop();
  net::loop();
  settings::loop();

  comms::Msg m;
  for (int i = 0; i < 6 && comms::pop(m); i++) {
    if (m.binary) handleBinary(m);
    else handleJson(m);
    free(m.data);
  }

  if (io::booped()) {
    stats.boops++;
    stats.peakRapid = max<uint32_t>(stats.peakRapid, io::rapidBoops());
    if (stats.boops % 25 == 0) settings::saveStats();
    if (cfg.boopOn && mode == Mode::Face) boopUntil = now + cfg.boopMs;
    comms::broadcast(String("{\"t\":\"boop\",\"n\":") + stats.boops + "}");
  }

  io::Button b = io::button();
  if (mode == Mode::Game) {
    if (b == io::Button::Short) games::key(games::A, true), games::key(games::A, false);
    if (b == io::Button::Long) activate(cfg.active);
  } else if (b == io::Button::Short) {
    if (mode == Mode::Face || mode == Mode::Anim) nextExpression(1);
    else activate(cfg.active);
  } else if (b == io::Button::Long) {
    activate(0);
  }

  Layout layout = Layout::Mirror;
  switch (mode) {
    case Mode::Face: {
      canvas.clear();
      faces::FrameState f{t, blinkAmount(dt), io::micLevel()};
      faces::render(canvas, now < boopUntil ? cfg.boopExpr : cfg.active, f);
      layout = cfg.mirror ? Layout::Mirror : Layout::Duplicate;
      break;
    }
    case Mode::Anim:
      layout = anim::draw(canvas);
      break;
    case Mode::Text:
      renderText(dt);
      layout = Layout::Span;
      break;
    case Mode::Game:
      if (games::update(canvas, dt)) markDirty();
      layout = Layout::Span;
      break;
    case Mode::Draw:
      layout = drawLayout;
      break;
    case Mode::Test:
      renderTest();
      layout = Layout::Span;
      break;
  }
  display::present(canvas, layout);
  updateCheeks(t);

  if (meterUntil && now < meterUntil) {
    static uint32_t lastMeter = 0;
    if (now - lastMeter > 120) {
      lastMeter = now;
      comms::reply(meterSrc, meterClient,
                   String("{\"t\":\"meter\",\"mic\":") + String(io::micLevel(), 2) + ",\"raw\":" + io::micRaw() + "}");
    }
  }
  if (stateDirty && now - lastState > 300) {
    stateDirty = false;
    lastState = now;
    comms::broadcast(stateJson());
  }

  // ~60 fps; the rest of the frame budget goes to Wi-Fi and BLE tasks.
  uint32_t spent = millis() - now;
  if (spent < 16) delay(16 - spent);
}
