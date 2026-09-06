#include "x2c.x"

typedef List Row;

static inline Var Row.var(Row value) {
  return Var.new(<list>, value);
}

static inline Row Var.row(Var value) {
  return value.list();
}

String Row.summary(Row value) {
  return %"row:${value.len()}";
}

protocol Var(Row) as List;

typedef List PlainRow;

static inline Var PlainRow.var(PlainRow value) {
  return Var.new(<plainrow>, value);
}

static inline PlainRow Var.plainrow(Var value) {
  return (PlainRow) value.pointer();
}

protocol Var(PlainRow);

typedef PlainRow PlainRowChild;

typedef struct Cell {
  int value;
} *Cell;

static inline Var Cell.var(Cell value) {
  return Var.new(<p48>, value);
}

static inline Cell Var.cell(Var value) {
  return value.pointer();
}

protocol Var(Cell) as void *;

int main(void) {
  Row row = %(one two);
  Cell cell = Scope.malloc(sizeof(struct Cell));
  cell.value = 7;
  Var boxed_row = row;
  Var boxed_cell = cell;
  PlainRowChild child = %(three four);
  Var boxed_child = child;
  Row recovered_row = boxed_row;
  Cell recovered_cell = boxed_cell;
  PlainRowChild recovered_child = boxed_child;

  printf("%s %s %d %d %d %d %d %d %d\n",
         recovered_row.summary(), boxed_row.str(), recovered_cell.value,
         boxed_row is Row, boxed_row is List,
         boxed_cell is Cell, boxed_cell is (void *),
         boxed_child is PlainRow, recovered_child.len());
  return 0;
}
