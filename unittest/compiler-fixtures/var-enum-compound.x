#include "x2c.x"

typedef enum Number {
  NUMBER_ZERO
} Number;

int main(void) {
  Number value = NUMBER_ZERO;
  Var increment = 1;
  value += increment;
  return 0;
}
