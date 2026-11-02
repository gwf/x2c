#include "x2c.x"

/* A callback adapter for a callback type with no parameters is declared
   with the `(void)` prototype that type has. */

typedef int (*Nullary)(void);

static int answer(void) {
  return 42;
}

static Nullary thunk = $x2c.callback.adapt(Nullary, answer);

static int call(Nullary f) => f();

int main(void) {
  printf("%d %d\n", thunk(), call(%!() => 7));
  return 0;
}
