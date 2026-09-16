#include "x2c.x"

/*  A finalizer runs on every path that leaves its region, so its statements
    are emitted once per path. A label among them would be defined more than
    once, which the C compiler rejects with a confusing message; x2c reports
    it at the label instead. */

int main(void) {
  int value = 0;
  try value = 1;
  finally {
    value += 1;
    if (value < 3) goto again;
again:
    value += 10;
  }
  printf("%d\n", value);
  return 0;
}
