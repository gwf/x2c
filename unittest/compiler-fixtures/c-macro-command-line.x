#include "x2c.x"

// `-D` and `-U` define and undefine macros for x2c as for the C compiler,
// so their conditions are decided and their uses expand.
#ifdef ENABLED
int enabled(void) { return FEATURE; }
#else
not x2c
#endif

#ifdef REMOVED
not x2c either
#endif
