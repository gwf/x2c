#include "x2c.x"
#include "c-macro-include/defs.x"

// A macro an included x2c file defines expands in the includer, as the C
// compiler would expand it through the included file's generated header.
int scaled(int value) { return SCALED(value); }
