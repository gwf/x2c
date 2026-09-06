#include "x2c.x"
#include <limits.h>

static Var box_value(long value) {
  return value;
}

static long unbox_value(Var value) {
  return value;
}

int main(void) {
  long value = LONG_MAX;
  Var boxed = box_value(value);
  Array values = %[];
  values.push(value);
  long from_array = values[0];
  printf("%d %d %ld\n", boxed is <long>,
         unbox_value(boxed) == value, from_array);
  return from_array != value;
}
