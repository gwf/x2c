#include "x2c.x"
#include <limits.h>

static Var box_value(unsigned long value) {
  return value;
}

static unsigned long unbox_value(Var value) {
  return value;
}

int main(void) {
  unsigned long value = ULONG_MAX;
  Var boxed = box_value(value);
  unsigned long roundtrip = unbox_value(boxed);
  printf("%d %d %lu\n", boxed is <ulong>, roundtrip == value, roundtrip);
  return roundtrip != value;
}
