#include "x2c.x"
#include <limits.h>

static Var box_value(unsigned long long value) {
  return value;
}

static unsigned long long unbox_value(Var value) {
  return value;
}

int main(void) {
  unsigned long long value = ULLONG_MAX;
  Var boxed = box_value(value);
  unsigned long long roundtrip = unbox_value(boxed);
  printf("%d %d %llu\n", boxed is <ullong>, roundtrip == value, roundtrip);
  return roundtrip != value;
}
