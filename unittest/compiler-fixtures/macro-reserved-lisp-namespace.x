#include "x2c.x"
#include "lisp-bindings.x"

/* The `lisp.*` macro namespace is reserved for compiler-shipped
   facilities, as `x2c.*` is, so a program cannot redefine one. */
macro Stmt $lisp.install(Expr $lisp, Name $group) { puts("replaced"); }
