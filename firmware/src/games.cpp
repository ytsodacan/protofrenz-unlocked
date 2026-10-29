#include "games.h"
#include "settings.h"

namespace games {

static const char* const NAMES[] = {"Snake", "Paddle Duel", "Brick Breaker", "Comet Dodge"};
static const char* const SLUGS[] = {"snake", "paddle", "bricks", "comet"};
static const char* const KEYS[] = {"up", "down", "left", "right", "a", "b"};

static int cur = None;
static int pts = 0;
static bool over = false, newHigh = false;
static float overT = 0;
static bool held[KEY_COUNT], pressed[KEY_COUNT];

const char* name(int id) { return id >= 0 && id < COUNT ? NAMES[id] : ""; }
const char* slug(int id) { return id >= 0 && id < COUNT ? SLUGS[id] : ""; }
int fromSlug(const char* s) {
  for (int i = 0; i < COUNT; i++)
    if (s && !strcmp(s, SLUGS[i])) return i;
  return None;
}
bool keyFromName(const char* s, Key& out) {
  for (int i = 0; i < KEY_COUNT; i++)
    if (s && !strcmp(s, KEYS[i])) {
      out = (Key)i;
      return true;
    }
  return false;
}
int current() { return cur; }
int score() { return pts; }

void key(Key k, bool down) {
  if (down && !held[k]) pressed[k] = true;
  held[k] = down;
}

static bool take(Key k) {
  bool p = pressed[k];
  pressed[k] = false;
  return p;
}

static void text(Canvas& c, int x, int y, const char* s, RGB col, uint8_t size = 1) {
  c.setTextSize(size);
  c.setTextWrap(false);
  c.setTextColor(rgb565(col));
  c.setCursor(x, y);
  c.print(s);
}

static int textW(const char* s, uint8_t size = 1) { return strlen(s) * 6 * size; }

// ---------------------------------------------------------------- Snake
namespace snake {
constexpr int GW = 64, GH = 16;  // 2x2 pixel cells
static int8_t bx[GW * GH], by[GW * GH];
static int len, dir, nextDir, fx, fy;
static float acc;

static void placeFood() {
  for (;;) {
    fx = random(GW);
    fy = random(GH);
    bool hit = false;
    for (int i = 0; i < len; i++) hit |= bx[i] == fx && by[i] == fy;
    if (!hit) return;
  }
}

static void reset() {
  len = 4;
  for (int i = 0; i < len; i++) {
    bx[i] = 20 - i;
    by[i] = 8;
  }
  dir = nextDir = 0;
  acc = 0;
  placeFood();
}

static void step(float dt) {
  const int dx[] = {1, 0, -1, 0}, dy[] = {0, 1, 0, -1};
  if (take(Right) && dir != 2) nextDir = 0;
  if (take(Down) && dir != 3) nextDir = 1;
  if (take(Left) && dir != 0) nextDir = 2;
  if (take(Up) && dir != 1) nextDir = 3;
  acc += dt;
  float interval = max(0.045f, 0.14f - pts * 0.003f);
  if (acc < interval) return;
  acc = 0;
  dir = nextDir;
  int nx = (bx[0] + dx[dir] + GW) % GW, ny = (by[0] + dy[dir] + GH) % GH;
  for (int i = 0; i < len - 1; i++)
    if (bx[i] == nx && by[i] == ny) {
      over = true;
      return;
    }
  bool ate = nx == fx && ny == fy;
  if (ate && len < GW * GH) len++;
  for (int i = len - 1; i > 0; i--) {
    bx[i] = bx[i - 1];
    by[i] = by[i - 1];
  }
  bx[0] = nx;
  by[0] = ny;
  if (ate) {
    pts++;
    placeFood();
  }
}

static void draw(Canvas& c, float t) {
  for (int i = 0; i < len; i++) {
    RGB col = hsv(0.33f + i * 0.012f, 1, i == 0 ? 1 : 0.85f);
    c.fillRect(bx[i] * 2, by[i] * 2, 2, 2, rgb565(col));
  }
  RGB food = (int(t * 6) % 2) ? RGB{255, 60, 120} : RGB{255, 200, 0};
  c.fillRect(fx * 2, fy * 2, 2, 2, rgb565(food));
}
}  // namespace snake

// ---------------------------------------------------------------- Paddle Duel
namespace paddle {
static float py, ay, bx, by, vx, vy;
static int you, cpu;
static void serve(int towards) {
  bx = 64;
  by = 16;
  vx = 38.0f * towards;
  vy = random(-20, 21);
}
static void reset() {
  py = ay = 12;
  you = cpu = 0;
  serve(1);
}
static void step(float dt) {
  if (held[Up]) py -= 42 * dt;
  if (held[Down]) py += 42 * dt;
  py = constrain(py, 0.0f, 24.0f);
  float aim = by - 4;
  ay += constrain(aim - ay, -30 * dt, 30 * dt);
  ay = constrain(ay, 0.0f, 24.0f);
  bx += vx * dt;
  by += vy * dt;
  if (by < 0 || by > 31) {
    vy = -vy;
    by = constrain(by, 0.0f, 31.0f);
  }
  auto hit = [&](float padY, bool left) {
    float rel = (by - (padY + 4)) / 4.5f;
    vx = (left ? 1 : -1) * min(fabsf(vx) * 1.06f, 110.0f);
    vy = rel * 34;
  };
  if (vx < 0 && bx <= 3 && bx >= 1 && by >= py - 1 && by <= py + 9) hit(py, true);
  if (vx > 0 && bx >= 124 && bx <= 126 && by >= ay - 1 && by <= ay + 9) hit(ay, false);
  if (bx < -2) {
    cpu++;
    serve(1);
  }
  if (bx > 130) {
    you++;
    pts++;
    serve(-1);
  }
  if (you >= 7 || cpu >= 7) over = true;
}
static void draw(Canvas& c) {
  for (int y = 0; y < 32; y += 4) c.drawFastVLine(64, y, 2, rgb565({40, 40, 70}));
  c.fillRect(1, int(py), 2, 8, rgb565({0, 229, 255}));
  c.fillRect(125, int(ay), 2, 8, rgb565({255, 63, 164}));
  c.fillRect(int(bx), int(by), 2, 2, rgb565({255, 255, 255}));
  char s[4];
  snprintf(s, sizeof(s), "%d", you);
  text(c, 52, 1, s, {0, 120, 140});
  snprintf(s, sizeof(s), "%d", cpu);
  text(c, 71, 1, s, {140, 30, 90});
}
}  // namespace paddle

// ---------------------------------------------------------------- Brick Breaker (sideways)
namespace bricks {
constexpr int COLS = 6, ROWS = 8;  // columns of bricks on the right, 4x4 each
static bool alive[COLS][ROWS];
static float py, bx, by, vx, vy;
static int lives, left;
static bool stuck;
static void level() {
  left = 0;
  for (int i = 0; i < COLS; i++)
    for (int j = 0; j < ROWS; j++) alive[i][j] = true, left++;
  stuck = true;
}
static void reset() {
  py = 12;
  lives = 3;
  level();
}
static void step(float dt) {
  if (held[Up]) py -= 46 * dt;
  if (held[Down]) py += 46 * dt;
  py = constrain(py, 0.0f, 24.0f);
  if (stuck) {
    bx = 5;
    by = py + 3;
    if (take(A) || take(Right)) {
      stuck = false;
      vx = 44;
      vy = random(-16, 17);
    }
    return;
  }
  bx += vx * dt;
  by += vy * dt;
  if (by < 0 || by > 30) vy = -vy, by = constrain(by, 0.0f, 30.0f);
  if (bx > 126) vx = -fabsf(vx);
  if (vx < 0 && bx <= 4 && bx >= 2 && by >= py - 2 && by <= py + 9) {
    vx = fabsf(vx) * 1.02f;
    vy = ((by - (py + 4)) / 4.5f) * 36;
  }
  if (bx < 0) {
    if (--lives <= 0) over = true;
    stuck = true;
    return;
  }
  int i = (int(bx) - 100) / 4, j = int(by) / 4;
  if (i >= 0 && i < COLS && j >= 0 && j < ROWS && alive[i][j]) {
    alive[i][j] = false;
    vx = -vx;
    pts++;
    if (--left == 0) level();
  }
}
static void draw(Canvas& c) {
  for (int i = 0; i < COLS; i++)
    for (int j = 0; j < ROWS; j++)
      if (alive[i][j]) c.fillRect(100 + i * 4, j * 4, 3, 3, rgb565(hsv(j / float(ROWS), 0.8f, 1)));
  c.fillRect(2, int(py), 2, 8, rgb565({0, 229, 255}));
  c.fillRect(int(bx), int(by), 2, 2, rgb565({255, 255, 255}));
  for (int k = 0; k < lives; k++) c.fillRect(56 + k * 5, 0, 3, 1, rgb565({255, 63, 164}));
}
}  // namespace bricks

// ---------------------------------------------------------------- Comet Dodge
namespace comet {
constexpr int N = 10;
static float sy, cx[N], cy[N], cv[N], starX, starY, dist;
static uint8_t cs[N];
static void spawn(int i) {
  cx[i] = 128 + random(0, 80);
  cy[i] = random(0, 30);
  cv[i] = 30 + random(0, 25) + dist * 0.02f;
  cs[i] = random(1, 4);
}
static void reset() {
  sy = 14;
  dist = 0;
  for (int i = 0; i < N; i++) spawn(i), cx[i] += i * 14;
  starX = 140;
  starY = random(2, 28);
}
static void step(float dt) {
  if (held[Up]) sy -= 40 * dt;
  if (held[Down]) sy += 40 * dt;
  sy = constrain(sy, 0.0f, 28.0f);
  dist += dt * 60;
  pts = int(dist / 10);
  for (int i = 0; i < N; i++) {
    cx[i] -= cv[i] * dt;
    if (cx[i] < -4) spawn(i);
    if (cx[i] < 10 && cx[i] + cs[i] > 3 && cy[i] + cs[i] > sy && cy[i] < sy + 4) over = true;
  }
  starX -= 35 * dt;
  if (starX < 10 && starX > 2 && fabsf(starY - (sy + 2)) < 4) {
    dist += 100;
    starX = 160 + random(0, 60);
    starY = random(2, 28);
  }
  if (starX < -4) starX = 160, starY = random(2, 28);
}
static void draw(Canvas& c, float t) {
  for (int k = 0; k < 24; k++) {  // parallax dust
    int x = (int(k * 37 - t * (10 + k % 3 * 12)) % 128 + 128) % 128;
    c.drawPixel(x, (k * 11) % 32, rgb565({30, 30, 50}));
  }
  c.fillTriangle(3, int(sy), 3, int(sy) + 4, 9, int(sy) + 2, rgb565({0, 229, 255}));
  c.drawPixel(2, int(sy) + 2, rgb565({255, 140, 0}));
  for (int i = 0; i < N; i++) {
    c.fillRect(int(cx[i]), int(cy[i]), cs[i] + 1, cs[i] + 1, rgb565({255, 90, 40}));
    c.drawFastHLine(int(cx[i]) + cs[i] + 1, int(cy[i]) + cs[i] / 2, 4, rgb565({90, 30, 10}));
  }
  RGB star = hsv(t * 0.8f, 0.6f, 1);
  c.drawPixel(int(starX), int(starY), rgb565(star));
  c.drawPixel(int(starX) - 1, int(starY), rgb565(star));
  c.drawPixel(int(starX) + 1, int(starY), rgb565(star));
  c.drawPixel(int(starX), int(starY) - 1, rgb565(star));
  c.drawPixel(int(starX), int(starY) + 1, rgb565(star));
}
}  // namespace comet

void start(int id) {
  cur = id;
  pts = 0;
  over = false;
  newHigh = false;
  overT = 0;
  memset(held, 0, sizeof(held));
  memset(pressed, 0, sizeof(pressed));
  switch (cur) {
    case Snake: snake::reset(); break;
    case Paddle: paddle::reset(); break;
    case Bricks: bricks::reset(); break;
    case Comet: comet::reset(); break;
    default: cur = None;
  }
}

void stop() { cur = None; }

bool update(Canvas& c, float dt) {
  static float t = 0;
  t += dt;
  c.clear();
  if (cur == None) return false;
  dt = min(dt, 0.05f);
  bool justEnded = false;
  if (!over) {
    switch (cur) {
      case Snake: snake::step(dt); break;
      case Paddle: paddle::step(dt); break;
      case Bricks: bricks::step(dt); break;
      case Comet: comet::step(dt); break;
    }
    if (over) {
      justEnded = true;
      if (pts > stats.hiscore[cur]) {
        stats.hiscore[cur] = pts;
        newHigh = true;
        settings::saveStats();
      }
    }
  }
  switch (cur) {
    case Snake: snake::draw(c, t); break;
    case Paddle: paddle::draw(c); break;
    case Bricks: bricks::draw(c); break;
    case Comet: comet::draw(c, t); break;
  }
  if (over) {
    overT += dt;
    c.fadeAll(70);
    const char* title = newHigh ? "NEW BEST!" : "GAME OVER";
    text(c, (128 - textW(title)) / 2, 6, title, newHigh ? hsv(t, 1, 1) : RGB{255, 63, 164});
    char s[24];
    snprintf(s, sizeof(s), "%d  best %d", pts, stats.hiscore[cur]);
    text(c, (128 - textW(s)) / 2, 18, s, {200, 200, 220});
    if (overT > 0.6f && (take(A) || take(B))) start(cur);
  }
  for (bool& p : pressed) p = false;
  return justEnded && newHigh;
}

}  // namespace games
