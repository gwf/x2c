// An import that an included file does not export stays in that file, so
// the Lisp definitions it evaluates do not reach the includer.
#include "macro-export-lisp.x"

int lisp = $(h_lisp);
