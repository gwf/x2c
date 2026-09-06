#include "x2c.x"

typedef unsigned int StaticNative;

static unsigned native_hash(unsigned value) {
  return value + 1;
}

protocol unsigned(T) {
  unsigned T.hash(T) = native_hash;
}

protocol unsigned(StaticNative);

int main(void) {
  StaticNative value = 41;
  printf("%u\n", value.hash());
  return 0;
}
