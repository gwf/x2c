#include "x2c.x"

static int _box_float(int value) { return value + 1; }

int main(void) {
  float value = 1.25f;
  Var boxed = value;
  printf("%d %.2f\n", _box_float(1), boxed.floating());
  return 0;
}
