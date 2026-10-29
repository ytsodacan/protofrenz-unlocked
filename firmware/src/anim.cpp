#include "anim.h"
#include <LittleFS.h>

namespace anim {

struct Header {
  char magic[4];
  uint16_t w, h, frames;
  uint8_t flags, pad;
} __attribute__((packed));

static File file;
static Header hdr;
static char curName[40] = "";
static uint16_t frameIdx = 0;
static uint32_t nextAt = 0;
static bool shown = false;
static uint16_t lineBuf[VISOR_W];

static File up;
static uint32_t upSize = 0, upGot = 0;
static char upName[40];

static void safeName(const char* in, char* out, size_t n) {
  size_t j = 0;
  for (size_t i = 0; in && in[i] && j < n - 5; i++) {
    char ch = in[i];
    if (isalnum((unsigned char)ch) || ch == '-' || ch == '_' || ch == ' ') out[j++] = ch;
  }
  out[j] = 0;
  if (!j) strcpy(out, "anim");
}

static String pathFor(const char* name) {
  char clean[36];
  safeName(name, clean, sizeof(clean));
  return String("/anim/") + clean + ".pfa";
}

bool begin() {
  if (!LittleFS.begin(true, "/littlefs", 10, "spiffs")) return false;
  if (!LittleFS.exists("/anim")) LittleFS.mkdir("/anim");
  return true;
}

static bool readHeader(File& f, Header& h) {
  if (f.read((uint8_t*)&h, sizeof(h)) != sizeof(h)) return false;
  return !memcmp(h.magic, "PFA1", 4) && (h.w == PANEL_W || h.w == VISOR_W) && h.h == PANEL_H && h.frames;
}

void list(JsonArray out) {
  File dir = LittleFS.open("/anim");
  for (File f = dir.openNextFile(); f; f = dir.openNextFile()) {
    String n = f.name();
    if (!n.endsWith(".pfa")) continue;
    Header h;
    bool ok = readHeader(f, h);
    JsonObject o = out.add<JsonObject>();
    o["name"] = n.substring(0, n.length() - 4);
    o["size"] = f.size();
    o["frames"] = ok ? h.frames : 0;
    o["w"] = ok ? h.w : 0;
  }
}

bool remove(const char* name) {
  if (playing() && !strcmp(name, curName)) stop();
  return LittleFS.remove(pathFor(name));
}

void fsInfo(JsonObject out) {
  out["total"] = LittleFS.totalBytes();
  out["used"] = LittleFS.usedBytes();
}

bool play(const char* name) {
  stop();
  file = LittleFS.open(pathFor(name), "r");
  if (!file || !readHeader(file, hdr)) {
    stop();
    return false;
  }
  safeName(name, curName, sizeof(curName));
  frameIdx = 0;
  nextAt = 0;
  shown = false;
  return true;
}

void stop() {
  if (file) file.close();
  curName[0] = 0;
}

bool playing() { return (bool)file; }
const char* current() { return curName; }

Layout draw(Canvas& c) {
  Layout layout = hdr.w == VISOR_W ? Layout::Span : (hdr.flags & FLAG_MIRROR) ? Layout::Mirror : Layout::Duplicate;
  if (!file) return layout;
  uint32_t now = millis();
  if (shown && now < nextAt) return layout;

  if (frameIdx >= hdr.frames) {
    frameIdx = 0;
    file.seek(sizeof(Header));
  }
  uint16_t delayMs = 100;
  file.read((uint8_t*)&delayMs, 2);
  for (int y = 0; y < hdr.h; y++) {
    file.read((uint8_t*)lineBuf, hdr.w * 2);
    for (int x = 0; x < hdr.w; x++) c.set(x, y, from565(lineBuf[x]));
  }
  frameIdx++;
  nextAt = now + max<uint16_t>(delayMs, 16);
  shown = true;
  return layout;
}

static bool upRaw = false;

bool uploadBegin(const char* name, uint32_t size, bool raw) {
  if (up) up.close();
  upRaw = raw;
  safeName(name, upName, sizeof(upName));
  if (size > LittleFS.totalBytes() - LittleFS.usedBytes()) return false;
  up = LittleFS.open("/anim/upload.tmp", "w");
  upSize = size;
  upGot = 0;
  return (bool)up;
}

bool uploadChunk(uint32_t offset, const uint8_t* data, size_t len) {
  if (!up || offset != upGot) return false;
  if (up.write(data, len) != len) return false;
  upGot += len;
  return true;
}

bool uploadEnd() {
  if (!up) return false;
  up.close();
  if (upGot != upSize) {
    LittleFS.remove("/anim/upload.tmp");
    return false;
  }
  if (upRaw) {  // non-animation payload (face pack): caller validates it at its final path
    String dst = String("/") + upName;
    LittleFS.remove(dst);
    return LittleFS.rename("/anim/upload.tmp", dst);
  }
  File f = LittleFS.open("/anim/upload.tmp", "r");
  Header h;
  bool ok = readHeader(f, h) && f.size() == sizeof(Header) + (uint32_t)h.frames * (2 + h.w * h.h * 2);
  f.close();
  if (!ok) {
    LittleFS.remove("/anim/upload.tmp");
    return false;
  }
  String dst = pathFor(upName);
  if (playing() && !strcmp(curName, upName)) stop();
  LittleFS.remove(dst);
  return LittleFS.rename("/anim/upload.tmp", dst);
}

uint32_t uploadReceived() { return upGot; }
bool uploadWasRaw() { return upRaw; }

}  // namespace anim
