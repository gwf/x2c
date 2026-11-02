#include "x2c.x"

/* An expand row gives a Name hole the name a source argument would: an
   Atom row, short or long, is that name's spelling, as a String row is. */
int main(void) {
  int total = 0;
  expand %(alpha (beta) "gamma" running_total)
  macro Stmt(Name $name) { int $name = 2; total += $name; }
  printf("%d %d %d %d %d\n", alpha, beta, gamma, running_total, total);
  return 0;
}
