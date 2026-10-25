#include "x2c.x"

int main(void) {
  int value = 1;
  alias value as copy;
  if (value) unalias copy;
  return copy;
}
