#include "x2c.x"
#include "cpp-include-group/limits.x"

// Collection reads the header's `#ifndef LIM_SIZE` arm as a linear reading
// does, with `LIM_SIZE` not yet defined, so it records `lim_default`.
int limit(void) { return lim_default() + LIM_SIZE; }
