#include "x2c.x"

static int invoke(int value, int callback(int)) {
  return callback(value);
}

int main(void) {
  return invoke(41, %!(value) => value.int() + 1) != 42;
}
