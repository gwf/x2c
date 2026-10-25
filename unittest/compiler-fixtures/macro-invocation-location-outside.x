#include "x2c.x"

/* The compiler means to reject the invocation location outside an
   expansion, but a file-scope `$` call currently answers with its own
   location; unittest/STATUS.md tracks the gap. */
static char *file = $x2c_invocation_file();
static int line = $x2c_invocation_line();
