#include "x2c.x"
// Only the host preprocessor expands the macro: x2c cannot decide __GNUC__.
#ifdef __GNUC__
#define MISSING $(import "missing.xlisp")
#endif

MISSING
