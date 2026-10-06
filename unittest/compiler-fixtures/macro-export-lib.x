#include "x2c.x"
#include "macro-export.x"
$(import "macro-export.xlisp")
#include "macro-export-hidden.x"

int lib_value = $m.value() + 1;
