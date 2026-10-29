#include "x2c.x"
// Only the host preprocessor expands the macro: x2c cannot decide the flag.
#ifndef FIXTURE_HOST_FLAG
#define MISSING $(import "missing.xlisp")
#endif

MISSING
