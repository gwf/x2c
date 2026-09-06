#include "x2c.x"

typedef List Row;
Var Row.var(Row);
Row Var.row(Var);

protocol Var(Row) as List tag <row>;
