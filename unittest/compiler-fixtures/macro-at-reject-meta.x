#include "x2c.x"
#include "meta.x"

meta static List rows(void) => NULL;
macro Stmt $old() { $rows()... }
