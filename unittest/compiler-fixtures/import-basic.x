/*  import-basic.x -- consumer of the geo toy package.

    The alias is resolution-only: every generated C name carries the
    package's own geo__ prefix.
*/
#pragma once

import "geo" as g;

int main(void);

#pragma private

#include <stdio.h>

int main(void) {
  g.Vec v = g.Vec.new(3.0, 4.0);
  g.VecPair pair;
  pair.a.x = 1.0; pair.a.y = 0.0;
  pair.b.x = 0.0; pair.b.y = 2.0;
  printf("norm=%g span=%g\n", v.norm(), g.span(pair));
  return 0;
}
