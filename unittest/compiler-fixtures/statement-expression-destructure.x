#include "x2c.x"

typedef List Values;
static int calls, cleanups;

macro Expression $wrapped(Expr $value) =>
  $(list 'expr '() (list 'parens
    (list 'at 'm-origin (list 'at 'm-origin
      (list 'block (list 'stmnt $value))))));

static Values once(Values values) {
  calls++;
  return values;
}

int main(void) {
  Values values = %(1 2);
  Var first = 0, second = 0, third = 0, fourth = 0;
  Values copy = ({ (first, second) = once(values); });
  Values direct = (third, fourth) = once(values);
  { defer cleanups++; (first, second) = once(values); }
  printf("%d %d %ld %ld %ld %ld %d %d\n", copy === values,
         direct === values, first.integer(), second.integer(),
         third.integer(), fourth.integer(), calls, cleanups);
  Values wrapped = $wrapped((first, second) = once(values));
  printf("%d %ld %ld %d\n", wrapped === values, first.integer(),
         second.integer(), calls);
  return 0;
}
