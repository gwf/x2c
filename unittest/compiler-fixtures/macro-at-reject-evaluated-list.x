#include "x2c.x"
#include "meta.x"

/* An evaluated List is one expression; `...` cannot follow it. */
macro Stmt $old() { $(list)... }
