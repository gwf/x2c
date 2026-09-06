#include "x2c.x"

typedef List Values;

int main(void) {
  Values values = %(1 2);
  Var a, b, c, d;
  Values result = (c, d) = (a, b) = values;
  printf("%ld %ld %ld %ld %d\n",
         a.integer(), b.integer(), c.integer(), d.integer(),
         result === values);
  return result === values ? 0 : 1;
}
