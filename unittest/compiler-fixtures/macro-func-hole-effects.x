#include "x2c.x"

static Func adder;
static int reads;
static int next(void) { reads++; return 5; }
macro Expression $add_one(Expr $value) => adder($value + 1, 1);

int main(void) {
  adder = %!(a, b) => (int) a + (int) b;
  int direct = (int) adder(next() + 1, 1);
  int expanded = (int) $add_one(next());
  short value = 5;
  int converted = (int) $add_one(value);
  printf("%d %d %d %d\n", direct, expanded, converted, reads);
  return direct != 7 || expanded != direct || converted != 7 || reads != 2;
}
