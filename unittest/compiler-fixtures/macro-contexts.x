#include "x2c.x"

macro Expression $identity_lambda() => (%!(value) => value)

macro Unit $build_control(Expr $amount) => {
  static int $(x2c.ident "generated")(void) {
    int result = 0;
    for (int index = 0; index < 1; index++)
      result += $amount;
    while (result < $amount)
      result++;
    match (%(ready)) {
      case %(ready):
        result += 0;
    }
    return result;
  }
}

$build_control(42);

int main(void) {
  List values = %(42), copied = values.map($identity_lambda());
  printf("%d %d\n", generated(), copied[0].int());
  return 0;
}
