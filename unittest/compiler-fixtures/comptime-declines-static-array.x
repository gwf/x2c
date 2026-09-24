#include "x2c.x"

meta int array_value(void) {
  static int values[2] = {1, 2};
  return values[0];
}

int main(void) { return $array_value(); }
