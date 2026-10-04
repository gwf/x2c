#include "x2c.x"

/* A catch pattern binder in a template keeps its spelling when a hole of
   the macro has the same name. */
macro Stmt $caught(Expr $cause, Expr $value, Expr $result) {
  try raise %($cause (value ${$value}));
  catch %(?cause (value ?value) *rest):
    $result = cause == $cause && value == $value && !rest ? value : -1;
}

int main(void) {
  int first = 0, second = 0;
  $caught(<probe>, 3, first);
  $caught(<other>, 4, second);
  printf("%d %d\n", first, second);
  return first != 3 || second != 4;
}
