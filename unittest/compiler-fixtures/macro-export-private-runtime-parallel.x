// Static meta functions stay private at runtime and compile time.
#include "macro-export-lib.x"

int rt(void) => p_meta(1);
int rt_static(void) => p_static(1);
