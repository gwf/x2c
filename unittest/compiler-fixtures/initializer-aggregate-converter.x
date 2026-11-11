#include "x2c.x"

// A value the destination aggregate's converter accepts converts to the
// whole aggregate in a designated or positional initializer.
typedef struct Size { int unit; int amount; } Size;

Size int.size(int amount) => (Size){ 1, amount };

typedef struct Box { Size width; Size sides[2]; int depth; } Box;

static void show(Box box) {
  printf("%d:%d %d:%d %d:%d %d\n", box.width.unit, box.width.amount,
         box.sides[0].unit, box.sides[0].amount,
         box.sides[1].unit, box.sides[1].amount, box.depth);
}

int main(void) {
  Box designated = { .width = 5, .sides[1] = 7, .depth = 3 };
  show(designated);
  Box positional = { 5, { 6, 7 }, 3 };
  show(positional);
  show((Box){ .sides = { 8, 9 } });
  Size braced = { 2, 4 };
  Box nested = { .width = { 2, 4 }, .sides = { braced } };
  show(nested);
  return 0;
}
