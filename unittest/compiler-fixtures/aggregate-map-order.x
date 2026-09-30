#include "x2c.x"

static int mark(int *order, int digit, int value) {
  *order = *order * 10 + digit;
  return value;
}

macro Entry $two(Expr $first_key, Expr $first_value,
                 Expr $second_key, Expr $second_value) {
  $first_key: $first_value,
  $second_key: $second_value
}

int main(void) {
  int order = 0;
  Map values = %{
    ${mark(&order, 1, 1)}: ${mark(&order, 2, 10)},
    ${$two(mark(&order, 3, 2), mark(&order, 4, 20),
           mark(&order, 5, 1), mark(&order, 6, 30))}
  };
  if (order != 123456 || values.len() != 2 ||
      values[1].integer() != 30 || values[2].integer() != 20) return 1;
  printf("map row order ok\n");
  return 0;
}
