/*  alias-union-body.x -- alias and unalias among the members of a union */

#include "x2c.x"

typedef union Cell {
  alias 4 as size;
  char bytes[size];
  unalias size;
  alias 2 as half;
  char pair[half];
} Cell;

int main(void) {
  Cell cell;
  printf("%d %d\n", (int) sizeof(cell.bytes), (int) sizeof(cell.pair));
  return 0;
}
