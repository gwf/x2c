#include "x2c.x"

typedef struct Cell {
  double value;
} *Cell;

Var Cell.var(Cell cell) => Var.new(<cell>, cell);

Cell Var.cell(Var value) => (Cell) value.pointer();

Cell Cell.new(double value) {
  Cell cell = Scope.malloc(sizeof(struct Cell));
  cell.value = value;
  return cell;
}

/* The converter is the opt-in: a double beside a Cell becomes a Cell. */
Cell double.cell(double value) => Cell.new(value);

Cell Cell.mul(Cell a, Cell b) => Cell.new(a.value * b.value);

Cell Cell.sub(Cell a, Cell b) => Cell.new(a.value - b.value);

protocol Var(Cell);

int main(void) {
  Cell x = Cell.new(4.0);
  Cell y = 3.0 * x - 1.0;
  String text = "abc";
  printf("%g %s\n", y.value, text + 1);
  return 0;
}
