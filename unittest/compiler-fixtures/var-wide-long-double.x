#include "x2c.x"

static Var box_value(long double value) {
  return value;
}

static long double unbox_value(Var value) {
  return value;
}

int main(void) {
  long double value = 1.25L;
  Var boxed = box_value(value);
  long double roundtrip = unbox_value(boxed);
  printf("%d %d %.2Lf\n", boxed is <ldouble>, roundtrip == value, roundtrip);
  return roundtrip != value;
}
