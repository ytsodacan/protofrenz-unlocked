#include "display.h"
#include <ESP32-HUB75-MatrixPanel-I2S-DMA.h>

static MatrixPanel_I2S_DMA* dma = nullptr;
static uint8_t gammaLut[256];
static uint8_t targetBright = 96;
static float shownBright = 0;  // starts dark: the face fades in on boot
static bool swapP = false, rot = false;

void Canvas::drawPixel(int16_t x, int16_t y, uint16_t c) { set(x, y, from565(c)); }

void Canvas::fadeAll(uint8_t keep) {
  for (int y = 0; y < VISOR_H; y++)
    for (int x = 0; x < VISOR_W; x++) {
      RGB& p = px[y][x];
      p = {uint8_t(p.r * keep / 255), uint8_t(p.g * keep / 255), uint8_t(p.b * keep / 255)};
    }
}

uint16_t rgb565(RGB c) { return ((c.r & 0xF8) << 8) | ((c.g & 0xFC) << 3) | (c.b >> 3); }

RGB from565(uint16_t c) {
  uint8_t r = (c >> 11) & 0x1F, g = (c >> 5) & 0x3F, b = c & 0x1F;
  return {uint8_t((r << 3) | (r >> 2)), uint8_t((g << 2) | (g >> 4)), uint8_t((b << 3) | (b >> 2))};
}

RGB fromHex(uint32_t v) { return {uint8_t(v >> 16), uint8_t(v >> 8), uint8_t(v)}; }

RGB lerp(RGB a, RGB b, float t) {
  return {uint8_t(a.r + (b.r - a.r) * t), uint8_t(a.g + (b.g - a.g) * t), uint8_t(a.b + (b.b - a.b) * t)};
}

RGB hsv(float h, float s, float v) {
  h = h - floorf(h);
  float i = floorf(h * 6), f = h * 6 - i;
  float p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  float r, g, b;
  switch (int(i) % 6) {
    case 0: r = v, g = t, b = p; break;
    case 1: r = q, g = v, b = p; break;
    case 2: r = p, g = v, b = t; break;
    case 3: r = p, g = q, b = v; break;
    case 4: r = t, g = p, b = v; break;
    default: r = v, g = p, b = q; break;
  }
  return {uint8_t(r * 255), uint8_t(g * 255), uint8_t(b * 255)};
}

namespace display {

bool begin(uint8_t driver) {
  for (int i = 0; i < 256; i++) gammaLut[i] = uint8_t(powf(i / 255.0f, 2.2f) * 255 + 0.5f);

  HUB75_I2S_CFG::i2s_pins p = {pins::HUB_R1, pins::HUB_G1, pins::HUB_B1, pins::HUB_R2, pins::HUB_G2,
                               pins::HUB_B2, pins::HUB_A,  pins::HUB_B,  pins::HUB_C,  pins::HUB_D,
                               pins::HUB_E,  pins::HUB_LAT, pins::HUB_OE, pins::HUB_CLK};
  HUB75_I2S_CFG cfg(PANEL_W, PANEL_H, 2, p);
  cfg.double_buff = true;
  cfg.clkphase = false;
  cfg.min_refresh_rate = 120;
  const HUB75_I2S_CFG::shift_driver drivers[] = {HUB75_I2S_CFG::SHIFTREG, HUB75_I2S_CFG::FM6126A,
                                                 HUB75_I2S_CFG::ICN2038S, HUB75_I2S_CFG::MBI5124};
  cfg.driver = drivers[driver < 4 ? driver : 0];

  dma = new MatrixPanel_I2S_DMA(cfg);
  if (!dma->begin()) {
    delete dma;
    dma = nullptr;
    return false;
  }
  dma->setBrightness8(0);
  dma->clearScreen();
  dma->flipDMABuffer();
  dma->clearScreen();
  return true;
}

bool ok() { return dma != nullptr; }

void setBrightness(uint8_t b) { targetBright = b; }

void setOrientation(bool swapPanels, bool rotate180) {
  swapP = swapPanels;
  rot = rotate180;
}

void present(const Canvas& c, Layout layout) {
  if (!dma) return;
  // Ease brightness toward the target (boot fade-in and slider changes).
  shownBright += (targetBright - shownBright) * 0.12f;
  if (fabsf(targetBright - shownBright) < 0.5f) shownBright = targetBright;
  dma->setBrightness8(uint8_t(shownBright));

  for (int y = 0; y < VISOR_H; y++) {
    for (int x = 0; x < VISOR_W; x++) {
      int sx = x, sy = y;
      if (layout == Layout::Mirror) sx = x < PANEL_W ? x : (VISOR_W - 1 - x);
      else if (layout == Layout::Duplicate) sx = x % PANEL_W;
      const RGB& p = c.px[sy][sx];
      int dx = x, dy = y;
      if (swapP) dx = (dx + PANEL_W) % VISOR_W;
      if (rot) {
        dx = VISOR_W - 1 - dx;
        dy = VISOR_H - 1 - dy;
      }
      dma->drawPixelRGB888(dx, dy, gammaLut[p.r], gammaLut[p.g], gammaLut[p.b]);
    }
  }
  dma->flipDMABuffer();
}

}  // namespace display
