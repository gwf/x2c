#include "x2c.x"

static int cleanups;

macro Expression $make_fn() => %!(Var value) => ({
  { defer cleanups++; if (value.int() > 0) return 3; }
  4;
});

int main(void) {
  Func source = %!(Var value) => ({
    { defer cleanups++; if (value.int() > 0) return 3; }
    4;
  });
  Func constructed = $make_fn();
  Var first = source(1), second = source(0);
  Var third = constructed(1), fourth = constructed(0);
  printf("%ld %ld %ld %ld %d\n", first.integer(), second.integer(),
         third.integer(), fourth.integer(), cleanups);
  return 0;
}
