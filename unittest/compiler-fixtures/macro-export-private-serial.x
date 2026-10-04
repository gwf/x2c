// An import that an included file does not export stays in that file after
// a serial translation of that file, which the includer then replays.
#include "macro-export-lib.x"

int lisp = $(p_lisp);
int meta = $p_meta(1);
int expression = $p.value();
