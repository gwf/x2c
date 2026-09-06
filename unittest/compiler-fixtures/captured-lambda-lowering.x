#include "x2c.x"

static int live = 5;

static Func add_to(int bias) {
  return %!(int value) => value + bias + live;
}

static Func combine(int left, int right) {
  return %!(int value) => value + right + left + right;
}

static Func nest(int first) {
  return %!(int second) => %!(int value) => value + first + second;
}

static Func counter(int value) {
  return %!() using &value => ++value;
}

int main(void) {
  Func add_three = add_to(3);
  Func combined = combine(10, 20);
  Func middle = nest(4);
  Func inner = middle(5);
  Func count = counter(0);
  int direct_bias = 2, zero_value = 11;
  Var direct = (%!(int value) => value + direct_bias)(5);
  Var zero = (%!() => zero_value)();
  live = 7;
  printf("%ld %ld %ld %ld %ld %ld %ld\n",
         add_three(4).integer(), combined(1).integer(),
         inner(6).integer(), direct.integer(), zero.integer(),
         count().integer(), count().integer());
  return 0;
}
