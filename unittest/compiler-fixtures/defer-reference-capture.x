#include "x2c.x"

/* A defer that reads a reference parameter captures the parameter's own
   address, so the cleanup sees the caller's object after the body changes
   it. */
typedef struct Counter { int value; } Counter;

static void show(Counter &counter) { printf("%d\n", counter.value); }

static void bump(Counter &counter) {
  defer show(counter);
  counter.value = 5;
}

int main(void) {
  Counter counter = {1};
  bump(counter);
  return 0;
}
