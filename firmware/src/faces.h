#pragma once
#include "display.h"
#include "settings.h"

namespace faces {
enum Part : uint8_t { Eye, Nose, Mouth };

bool vendor();  // true when built with tools/import_protofrenz_faces.py output
uint8_t count(Part p);
const char* name(Part p, uint8_t i);
void bits(Part p, uint8_t i, uint8_t* out);  // canonical bytes, size per part

struct FrameState {
  float t;      // seconds
  float blink;  // 0 open .. 1 closed
  float talk;   // 0..1 mic level
};

// Draws expression `ei` into the left 64x32 half of the canvas.
void render(Canvas& c, uint8_t ei, const FrameState& f);
RGB gradientAt(const Expression& e, float pos, float t);
}  // namespace faces
