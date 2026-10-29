#include "playground.h"
#include <stdlib.h>

struct PlaygroundHandle { int value; };
int playground_calls;

PlaygroundPoint *playground_new(int x, int y) {
  PlaygroundPoint *point = malloc(sizeof *point);
  point->x = x;
  point->y = y;
  playground_calls++;
  return point;
}

void playground_move(PlaygroundPoint *point, int dx) { point->x += dx; }
void playground_free(PlaygroundPoint *point) { free(point); }
PlaygroundPoint playground_value(int x, int y) {
  PlaygroundPoint point = { x, y };
  return point;
}

PlaygroundPacket playground_packet(unsigned char marker, int value) {
  PlaygroundPacket packet = { marker, value };
  return packet;
}

int playground_apply(PlaygroundPoint *point, int (*combine)(int, int)) {
  return combine(point->x, point->y);
}

PlaygroundHandle *playground_open(int value) {
  PlaygroundHandle *handle = malloc(sizeof *handle);
  handle->value = value;
  return handle;
}

int playground_read(PlaygroundHandle *handle) { return handle->value; }
void playground_close(PlaygroundHandle *handle) { free(handle); }
