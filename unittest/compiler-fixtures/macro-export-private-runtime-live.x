// An import that an included file does not export keeps its meta functions
// in that file with live preprocessor symbol collection. The includer's
// run-time call has no prototype.
#include "macro-export-lib.x"

int rt(void) => p_meta(1);
int rt_static(void) => p_static(1);
