#include "x2c.x"

/* `@name` and `@(expression)` splice a List's elements into an evaluated
   List, as in a quoted List. Each operand runs once, in source order. */
static List traced(int n, List xs) {
  printf("traced %d\n", n);
  return xs;
}

int main(void) {
  List none = %(), one = %(7), xs = %(1 2);
  Var boxed = %(3 4);
  printf("%s\n", $(@none).repr());
  printf("%s\n", $(@one).repr());
  printf("%s\n", $(@(traced(1, %())), 0, @(traced(2, xs)), 9).repr());
  printf("%s\n", $(@xs, $(@xs), xs, @boxed, @([5, 6])).repr());
  printf("%s\n", $(@(traced(3, xs)), traced(4, one)).repr());
  return 0;
}
