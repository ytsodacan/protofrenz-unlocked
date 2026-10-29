#include "faces.h"
#include <LittleFS.h>

#if __has_include("faces_vendor.h")
#include "faces_vendor.h"
#define FACES_VENDOR 1
#else
#include "faces_default.h"
#define FACES_VENDOR 0
#endif

namespace faces {

// Placement on the 64x32 panel, matching the stock ProtoFrenz layout.
struct Place {
  int ox, oy, w, h;
};
static constexpr Place EYE_AT = {4, 2, EYE_W, EYE_H};
static constexpr Place NOSE_AT = {52, 2, NOSE_W, NOSE_H};
static constexpr Place MOUTH_AT = {2, 18, MOUTH_W, MOUTH_H};
static constexpr float SCALE = 1.5f;

// Face pack uploaded by the app (/faces): "PFP1", u8 eyes, u8 noses, u8 mouths, u8 0,
// then for each eye, nose and mouth in turn: char name[16] + canonical bitmap.
static constexpr const char* PACK_PATH = "/faces";
static constexpr size_t NAME_LEN = 16;
static constexpr size_t PART_BYTES[3] = {EYE_BYTES, NOSE_BYTES, MOUTH_BYTES};
static uint8_t* pack = nullptr;
static uint8_t packCount[3] = {0, 0, 0};
static size_t packOffset[3];

static void unloadPack() {
  free(pack);
  pack = nullptr;
  memset(packCount, 0, sizeof(packCount));
}

bool loadPack() {
  unloadPack();
  File f = LittleFS.open(PACK_PATH, "r");
  if (!f) return false;
  uint8_t hdr[8];
  size_t size = f.size();
  bool ok = f.read(hdr, 8) == 8 && !memcmp(hdr, "PFP1", 4) && hdr[4] && hdr[5] && hdr[6];
  size_t need = 0;
  if (ok) {
    for (int p = 0; p < 3; p++) need += hdr[4 + p] * (NAME_LEN + PART_BYTES[p]);
    ok = size == 8 + need;
  }
  if (ok) {
    pack = (uint8_t*)malloc(need);
    ok = pack && f.read(pack, need) == need;
  }
  f.close();
  if (!ok) {
    unloadPack();
    LittleFS.remove(PACK_PATH);
    return false;
  }
  size_t off = 0;
  for (int p = 0; p < 3; p++) {
    packCount[p] = hdr[4 + p];
    packOffset[p] = off;
    off += packCount[p] * (NAME_LEN + PART_BYTES[p]);
  }
  return true;
}

void removePack() {
  unloadPack();
  LittleFS.remove(PACK_PATH);
}

bool hasPack() { return pack != nullptr; }
bool vendor() { return FACES_VENDOR; }

static const uint8_t* packItem(Part p, uint8_t i) {
  return pack + packOffset[p] + i * (NAME_LEN + PART_BYTES[p]);
}

uint8_t count(Part p) {
  if (pack) return packCount[p];
  return p == Eye ? FACE_EYES_COUNT : p == Nose ? FACE_NOSES_COUNT : FACE_MOUTHS_COUNT;
}

const char* name(Part p, uint8_t i) {
  i %= count(p);
  if (pack) {
    static char buf[NAME_LEN + 1];
    memcpy(buf, packItem(p, i), NAME_LEN);
    buf[NAME_LEN] = 0;
    return buf;
  }
  return p == Eye ? FACE_EYES_NAMES[i] : p == Nose ? FACE_NOSES_NAMES[i] : FACE_MOUTHS_NAMES[i];
}

void bits(Part p, uint8_t i, uint8_t* out) {
  i %= count(p);
  if (pack) memcpy(out, packItem(p, i) + NAME_LEN, PART_BYTES[p]);
  else if (p == Eye) memcpy_P(out, FACE_EYES[i], EYE_BYTES);
  else if (p == Nose) memcpy_P(out, FACE_NOSES[i], NOSE_BYTES);
  else memcpy_P(out, FACE_MOUTHS[i], MOUTH_BYTES);
}

static inline bool bitAt(const uint8_t* b, int w, int x, int y) {
  return (b[y * (w / 8) + x / 8] >> (7 - x % 8)) & 1;
}

static bool paintAt(const uint8_t* paint, int w, int h, int x, int y, RGB& out) {
  int cell = y * w + x;
  const uint8_t* mask = paint + w * h * 3;
  if (!((mask[cell / 8] >> (7 - cell % 8)) & 1)) return false;
  out = {paint[cell * 3], paint[cell * 3 + 1], paint[cell * 3 + 2]};
  return true;
}

RGB gradientAt(const Expression& e, float pos, float t) {
  float scroll = t * e.gradSpeed * 0.1f;
  switch (e.gradMode) {
    case GradMode::Solid:
      return fromHex(e.grad[0]);
    case GradMode::Rainbow:
      return hsv(pos * 0.6f - scroll, 1, 1);
    default:
      break;
  }
  if (e.gradCount <= 1) return fromHex(e.grad[0]);
  // Cyclic gradient so the scroll wraps seamlessly.
  float p = pos - scroll;
  p = (p - floorf(p)) * e.gradCount;
  int i = int(p) % e.gradCount;
  return lerp(fromHex(e.grad[i]), fromHex(e.grad[(i + 1) % e.gradCount]), p - floorf(p));
}

// Plots one source pixel at 1.5x, same rounding as the stock editor preview.
static void plot(Canvas& c, const Place& at, float sx, float sy, RGB col) {
  for (int dy = 0; dy < 2; dy++)
    for (int dx = 0; dx < 2; dx++) {
      int px = int(floorf(at.ox + sx * SCALE + dx + 0.5f));
      int py = int(floorf(at.oy + sy * SCALE + dy + 0.5f));
      if (px >= 0 && px < PANEL_W && py >= 0 && py < PANEL_H) c.set(px, py, col);
    }
}

static RGB colorFor(const Expression& e, int px, int py, float t) {
  float pos = e.gradMode == GradMode::Vertical ? py / float(PANEL_H) : px / float(PANEL_W);
  return gradientAt(e, pos, t);
}

void render(Canvas& c, uint8_t ei, const FrameState& f) {
  const Expression& e = cfg.expr[ei % EXPR_COUNT];
  uint8_t eye[EYE_BYTES], nose[NOSE_BYTES], mouth[MOUTH_BYTES];
  if (e.custom) {
    memcpy(eye, custom[ei].eye, EYE_BYTES);
    memcpy(nose, custom[ei].nose, NOSE_BYTES);
    memcpy(mouth, custom[ei].mouth, MOUTH_BYTES);
  } else {
    bits(Eye, e.eye, eye);
    bits(Nose, e.nose, nose);
    bits(Mouth, e.mouth, mouth);
  }
  bool painted = e.custom && ei == cfg.active;

  // Eye, squashed toward its centre line while blinking.
  float open = e.blink ? 1.0f - f.blink : 1.0f;
  const float mid = (EYE_H - 1) / 2.0f;
  for (int y = 0; y < EYE_H; y++)
    for (int x = 0; x < EYE_W; x++) {
      if (!bitAt(eye, EYE_W, x, y)) continue;
      float sy = open < 0.12f ? mid : mid + (y - mid) * open;
      RGB col;
      if (!(painted && activePaint.eyeOn && paintAt(activePaint.eye, EYE_W, EYE_H, x, y, col)))
        col = colorFor(e, EYE_AT.ox + x * SCALE, EYE_AT.oy + sy * SCALE, f.t);
      plot(c, EYE_AT, x, sy, col);
    }

  for (int y = 0; y < NOSE_H; y++)
    for (int x = 0; x < NOSE_W; x++)
      if (bitAt(nose, NOSE_W, x, y)) plot(c, NOSE_AT, x, y, colorFor(e, NOSE_AT.ox + x * SCALE, NOSE_AT.oy + y * SCALE, f.t));

  // Mouth: when talking, a second "jaw" copy drops by an amount that peaks mid-mouth.
  float talk = e.talk ? f.talk : 0;
  for (int y = 0; y < MOUTH_H; y++)
    for (int x = 0; x < MOUTH_W; x++) {
      if (!bitAt(mouth, MOUTH_W, x, y)) continue;
      RGB col;
      if (!(painted && activePaint.mouthOn && paintAt(activePaint.mouth, MOUTH_W, MOUTH_H, x, y, col)))
        col = colorFor(e, MOUTH_AT.ox + x * SCALE, MOUTH_AT.oy + y * SCALE, f.t);
      plot(c, MOUTH_AT, x, y, col);
      if (talk > 0.02f) {
        float drop = talk * 3.2f * sinf(PI * (x + 0.5f) / MOUTH_W);
        for (float d = 1; d <= drop + 0.01f; d += 1) plot(c, MOUTH_AT, x, y + d, lerp(col, {0, 0, 0}, 0.55f * (d < drop ? 1 : 0)));
        if (drop >= 1) plot(c, MOUTH_AT, x, y + drop, col);
      }
    }
}

}  // namespace faces
