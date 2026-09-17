#include <stdio.h>

struct Point { int x, y; } origin = { 1, 2 };
enum Mode { SLOW, FAST } mode = FAST;

struct Packet;
int fill(struct Packet *packet);
struct Packet { int size; };
int fill(struct Packet *packet) { return packet->size; }

int main(void) {
  struct Packet packet = { 5 };
  printf("%d %d %d %d\n", origin.x, origin.y, mode, fill(&packet));
  return 0;
}
