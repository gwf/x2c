// An import that an included file does not export stays in that file beside
// a parallel translation of that file: its Lisp definitions, meta
// functions, and macros.
#include "macro-export-lib.x"

int lisp = $(p_lisp);
int meta = $p_meta(1);
int expression = $p.value();
