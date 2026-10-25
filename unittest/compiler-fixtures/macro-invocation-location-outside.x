#include "x2c.x"

/* An invocation location exists only while a macro body is expanding. */
static char *file = $x2c_invocation_file();
static int line = $x2c_invocation_line();
