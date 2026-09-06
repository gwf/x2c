#include "x2c.x"
#include <limits.h>

static Var box_value(long long value) {
  return value;
}

static long long unbox_value(Var value) {
  return value;
}

int main(void) {
  long long value = LLONG_MIN;
  Var boxed = box_value(value);
  long long roundtrip = unbox_value(boxed);
  printf("%d %d %lld\n", boxed is <llong>, roundtrip == value, roundtrip);
  return roundtrip != value;
}
