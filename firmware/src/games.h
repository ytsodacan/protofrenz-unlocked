#pragma once
#include "display.h"

namespace games {
enum Id : int8_t { None = -1, Snake, Paddle, Bricks, Comet, COUNT };
enum Key : uint8_t { Up, Down, Left, Right, A, B, KEY_COUNT };

const char* name(int id);
const char* slug(int id);
int fromSlug(const char* s);
void start(int id);
void stop();
int current();
int score();
void key(Key k, bool down);
bool keyFromName(const char* s, Key& out);
// Steps the game and draws the full 128x32 frame. Returns true when a new high score was set.
bool update(Canvas& c, float dt);
}  // namespace games
