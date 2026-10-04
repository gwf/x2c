// A package that exports one macro pack and keeps another.
#include "x2c.x"
export $(import "tally.xmacro")
$(import "hidden.xmacro")

int base(void) => 1;
