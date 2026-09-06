#include "x2c.x"

typedef List Row;

static inline Var Row.var(Row value) {
  return Var.new(<list>, value);
}

static inline Row Var.row(Var value) {
  return value.list();
}

protocol Var(Row) as List;
protocol Var(Row) as Map;
