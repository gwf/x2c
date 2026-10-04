// A package whose exported packs depend on one another through top-level
// Lisp: the pack that zbase.x exports defines what this one calls.
#include "x2c.x"
#include "zbase.x"
export $(import "apack.xmacro")

int base(void) => 1;
