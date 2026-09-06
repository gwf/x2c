#include "x2c.x"
#include <stdio.h>

$x2c.foreign.alias(printf)
inline int alias_printf(const char *format, ...);
