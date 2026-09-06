#include "x2c.x"

typedef struct Bits {
  unsigned value : 4;
} Bits;

int main(void) {
  Bits bits = {0};
  Var increment = 1;
  bits.value += increment;
  return 0;
}
