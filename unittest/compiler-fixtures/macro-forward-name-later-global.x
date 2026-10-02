#include "x2c.x"

/* A macro body reaches a global declared after the definition. Its free
   name resolves where the expansion lands, so a caller's local of the same
   spelling supplies it there. */
macro Expression $read_later() => later + 1;
macro Statement $write_later(Expr $value) {
  later = $value;
}

int later = 3;

int main(void) {
  int before = $read_later();
  $write_later(10);
  int shadowed = 0;
  {
    int later = 7;
    shadowed = $read_later() + later;
  }
  printf("%d %d %d\n", before, later, shadowed);
  return before != 4 || later != 10 || shadowed != 15;
}
