#include "x2c.x"

int main(void) {
  int value = 1;
  with (value += 1) {
    value = 3;
  }
  return value;
}
