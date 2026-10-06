// Static compile-time definitions stay private to their source file.
#include "macro-export-lib.x"

int lisp = $(p_lisp);
int meta = $p_meta(1);
int expression = $p.value();
