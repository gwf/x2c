#include "x2c.x"

#define MEAN 0.5

typedef struct Cell {
  double value;
} *Cell;

protocol Arith(T) {
  T T.sub(T, T);
}

Cell Cell.new(double value) {
  Cell cell = Scope.calloc(1, sizeof(struct Cell));
  cell.value = value;
  return cell;
}

Cell double.cell(double value) => Cell.new(value);

Cell Cell.sub(Cell a, Cell b) => Cell.new(a.value - b.value);

protocol Arith(Cell);

int main(void) {
  Cell a = Cell.new(2.0);
  Cell shifted = a - MEAN;        // MEAN has no x2c type: rejected
  return (int) shifted.value;
}
