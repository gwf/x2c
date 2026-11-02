#include "x2c.x"

/* A function converted to Func inside a file-scope collection literal reads
   the function's shared handle, so the handle is assigned first. */

static Var twice(Var value) {
  return value * 2;
}

static Array private_table = [(Func) twice];
Array public_table = [(Func) twice];

int main(void) {
  Func first = private_table[0], second = public_table[0];
  printf("%s %s\n", first(21).repr(), second(4).repr());
  return 0;
}
