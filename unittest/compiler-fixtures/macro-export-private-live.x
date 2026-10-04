// An import that an included file does not export stays in that file with
// live symbol collection.
#include "macro-export-lisp.x"

int lisp = $(h_lisp);
