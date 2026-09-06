#include "x2c.x"
macro Expression $unused(Name $binding) => (%!() using &$binding => 42)
int main(void) {
  int unused;
  ScopeStats before = Scope.stats();
  Func outer = %!() => $unused(unused);
  Func inner = outer();
  ScopeStats after = Scope.stats();
  printf("value=%ld allocations=%lu\n", inner().integer(),
         after.allocation_calls - before.allocation_calls);
  return 0;
}
