#include "x2c.x"

static int total = 0;

macro Stmt $add(Expr $n) => total += $n;
macro Stmt $say(Expr $label, Expr $n) =>
  printf("%s\n", %"${$label} ${$n}");
macro Stmt $discard(Expr $value) => (void) $value;

int main(void) {
  macro Stmt bump() => total++;
  for (int i = 0; i < 3; i++) $add(i);
  if (total == 3) $say("three", total);
  else $say("other", total);
  while (total < 5) bump();
  $discard(total);
  $add(1); $say("end", total);
  return 0;
}
