#include "io.h"
#include <Adafruit_NeoPixel.h>
#include "settings.h"

namespace io {

static bool boopEdge = false, boopState = false;
static uint32_t boopChanged = 0;
static uint32_t boopTimes[16];
static uint8_t boopHead = 0;

static bool btnDown = false;
static uint32_t btnSince = 0;
static bool longFired = false;
static Button btnEvent = Button::None;

static float level = 0, floorLevel = 40;
static uint16_t lastRaw = 0;

static Adafruit_NeoPixel* strip = nullptr;
static constexpr uint8_t FAN_CH = 0;

void begin() {
  pinMode(pins::BOOP, INPUT);
  pinMode(pins::BUTTON, INPUT);
  pinMode(pins::MIC, INPUT);
  analogReadResolution(12);
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttachChannel(pins::FAN, 25000, 8, FAN_CH);
#else
  ledcSetup(FAN_CH, 25000, 8);
  ledcAttachPin(pins::FAN, FAN_CH);
#endif
  setFan(255);  // kick-start, then settle to the configured speed
  delay(200);
}

void setFan(uint8_t duty) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(pins::FAN, duty);
#else
  ledcWrite(FAN_CH, duty);
#endif
}

static void sampleMic() {
  uint16_t lo = 4095, hi = 0;
  for (int i = 0; i < 24; i++) {
    uint16_t v = analogRead(pins::MIC);
    lo = min(lo, v);
    hi = max(hi, v);
  }
  lastRaw = hi - lo;
  // Track the noise floor: fall fast, rise slowly.
  floorLevel = lastRaw < floorLevel ? floorLevel * 0.9f + lastRaw * 0.1f : floorLevel * 0.999f + lastRaw * 0.001f;
  float gain = cfg.micSens * 0.00035f;  // sens 5: full scale at ~600 counts peak-to-peak
  float target = constrain((lastRaw - floorLevel * 1.4f) * gain, 0.0f, 1.0f);
  level += (target - level) * (target > level ? 0.6f : 0.15f);
}

void loop() {
  uint32_t now = millis();
  bool b = digitalRead(pins::BOOP) == HIGH;
  if (b != boopState && now - boopChanged > 40) {
    boopState = b;
    boopChanged = now;
    if (b) {
      boopEdge = true;
      boopTimes[boopHead++ % 16] = now;
    }
  }

  bool down = digitalRead(pins::BUTTON) == LOW;
  if (down && !btnDown) {
    btnSince = now;
    longFired = false;
  } else if (down && !longFired && now - btnSince > 800) {
    longFired = true;
    btnEvent = Button::Long;
  } else if (!down && btnDown && !longFired && now - btnSince > 30) {
    btnEvent = Button::Short;
  }
  btnDown = down;

  sampleMic();
}

bool booped() {
  bool e = boopEdge;
  boopEdge = false;
  return e;
}

Button button() {
  Button e = btnEvent;
  btnEvent = Button::None;
  return e;
}

bool buttonHeld() { return btnDown; }
float micLevel() { return level; }
uint16_t micRaw() { return lastRaw; }

uint8_t rapidBoops() {
  uint8_t n = 0;
  for (uint32_t t : boopTimes)
    if (t && millis() - t < 5000) n++;
  return n;
}

void cheeksBegin(uint8_t count) {
  if (strip) {
    strip->clear();
    strip->show();
    delete strip;
    strip = nullptr;
  }
  if (!count) return;
  strip = new Adafruit_NeoPixel(count, pins::CHEEKS, NEO_GRB + NEO_KHZ800);
  strip->begin();
}

void cheeks(const RGB* colors, uint8_t n, uint8_t brightness) {
  if (!strip) return;
  strip->setBrightness(brightness);
  for (uint8_t i = 0; i < n && i < strip->numPixels(); i++) strip->setPixelColor(i, colors[i].r, colors[i].g, colors[i].b);
  strip->show();
}

}  // namespace io
