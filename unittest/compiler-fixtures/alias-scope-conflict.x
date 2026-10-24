#include "x2c.x"

int main(void) {
  int value = 1;
  alias value as copy;
  int copy = 2;
  return copy;
}
