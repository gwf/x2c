/*  import-using-order.x -- consumer of the usingorder toy package.

    A name a package macro lists with `using` keeps the package's
    declaration in an importing unit, whether the declaration comes before
    or after the macro: both calls use the `usingorder__` spelling. A
    native name keeps its own spelling, in an expression and in a declared
    array size.
*/
import "usingorder";

#include <stdio.h>

int main(void) {
  $sized(slots);
  printf("%d %d %d %d\n", $tripled(2), $doubled(2), $larger(1, 4), slots);
  return 0;
}
