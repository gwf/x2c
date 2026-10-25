#include "x2c.x"
#include "macro-type-fields-package-defs.x"

import "geo" as g;

macro Unit $check_imported(Type $type) {
  @same_fields($type,
    %(("a" (struct "geo__VecData")) ("b" (struct "geo__VecData"))),
    "imported fields differ")
}

$check_imported(g.VecPair);
