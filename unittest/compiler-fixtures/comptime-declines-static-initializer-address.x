#include "x2c.x"

meta int *remember(int seed) {
  int value = seed;
  static int *saved = &value;
  return saved;
}

int main(void) { return 0; }
