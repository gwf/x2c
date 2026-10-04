#include "x2c.x"
export $(import "macro-export.xmacro")
export $(import "macro-export.xlisp")
$(import "macro-export-hidden.xmacro")

int lib_value = $m.value() + $p.value();
