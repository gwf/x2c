#include "x2c.x"

/* A Name hole takes an Atom row's spelling, as it takes a String's. */
int main(void) {
  int total = 0;
  expand %(alpha beta)
  macro Stmt(Name $name) { int $name = 1; total += $name; }
  expand %("gamma")
  macro Stmt(Name $name) { int $name = 2; total += $name; }
  printf("%d %d\n", total, alpha + beta + gamma);
  return 0;
}
