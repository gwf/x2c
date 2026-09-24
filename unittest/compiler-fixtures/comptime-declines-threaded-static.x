#include "x2c.x"

meta int threaded_value(void) {
  static threaded int value = 1;
  return value;
}

int main(void) { return $threaded_value(); }
