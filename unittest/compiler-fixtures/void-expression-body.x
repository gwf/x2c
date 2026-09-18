#include "x2c.x"

typedef struct Counter { int value; } Counter;

static void Counter.step(Counter *self) => self.value++;

static void Counter.twice(Counter *self) => self.step();

static int Counter.read(Counter *self) => self.value;

static void *Counter.address(Counter *self) => self;

static void announce(int value) => printf("value %d\n", value);

int main(void) {
  Counter counter = { 0 };
  counter.step();
  counter.twice();
  announce(counter.read());
  printf("%d\n", counter.address() == &counter);
  return 0;
}
