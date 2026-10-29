#pragma once
#include <Adafruit_GFX.h>
#include "config.h"

struct RGB {
  uint8_t r, g, b;
};

// Full-visor RGB888 framebuffer. Faces draw into the left 64x32 half and
// present() mirrors it; text and games use the whole 128x32 span.
class Canvas : public Adafruit_GFX {
 public:
  Canvas() : Adafruit_GFX(VISOR_W, VISOR_H) {}
  void drawPixel(int16_t x, int16_t y, uint16_t c) override;
  void set(int x, int y, RGB c) {
    if ((unsigned)x < VISOR_W && (unsigned)y < VISOR_H) px[y][x] = c;
  }
  RGB get(int x, int y) const { return px[y][x]; }
  void clear() { memset(px, 0, sizeof(px)); }
  void fadeAll(uint8_t keep);  // scale every pixel by keep/255
  RGB px[VISOR_H][VISOR_W];
};

enum class Layout : uint8_t { Mirror, Duplicate, Span };

namespace display {
bool begin(uint8_t driver);
void present(const Canvas& c, Layout layout);
void setBrightness(uint8_t b);   // target; fades in smoothly
void setOrientation(bool swapPanels, bool rotate180);
bool ok();
}  // namespace display

uint16_t rgb565(RGB c);
RGB from565(uint16_t c);
RGB hsv(float h, float s, float v);
RGB lerp(RGB a, RGB b, float t);
RGB fromHex(uint32_t v);
