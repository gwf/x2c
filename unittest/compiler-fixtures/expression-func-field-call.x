/*  expression-func-field-call.x -- calling a `Func` field calls the
    function value it holds, through `.`, `->`, or parentheses alike.
*/
#include "x2c.x"

typedef struct Holder { Func f; } Holder;

int main(void) {
  Holder holder = { %!(int x) => x + 1 };
  Holder *pointer = &holder;
  Var direct = holder.f(41), arrow = pointer->f(1), grouped = (holder.f)(2);
  printf("%d %d %d\n", direct, arrow, grouped);
  return 0;
}
