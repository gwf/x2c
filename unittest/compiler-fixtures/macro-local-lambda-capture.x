#include "x2c.x"

int main(void) {
  Var typed = (%!(int base) => {
    macro Expression plus(Expr $value) => (base + $value)
    {
      int base = 100;
      return plus(3);
    }
  })(10);
  Var bare = (%!(base) => {
    macro Expression plus(Expr $value) => (base + $value)
    {
      int base = 100;
      return plus(4);
    }
  })(20);
  printf("%ld %ld\n", typed.integer(), bare.integer());
  return typed.integer() != 13 || bare.integer() != 24;
}
