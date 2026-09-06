#include "x2c.x"

macro Expression $snapshot(Name $binding) => (%!() => $binding)
macro Expression $increment(Name $binding) => (
  %!() using &$binding => ++$binding
)
macro Expression $shared_reader(Name $binding) => (
  %!() using &$binding => $binding
)

int main(void) {
  int value = 1;
  Func snapshot = $snapshot(value);
  Func increment = $increment(value);
  Func reader = $shared_reader(value);
  value = 2;
  long changed = increment().integer();
  printf("template snapshot=%ld increment=%ld reader=%ld outer=%d\n",
         snapshot().integer(), changed, reader().integer(), value);
  return 0;
}
