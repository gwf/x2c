// Public macros become visible at the include line. Earlier source cannot
// use them.
#include "x2c.x"

int early = $m.value();

#include "macro-export-lib.x"
