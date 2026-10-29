#include "x2c.x"

// A use with the wrong number of arguments is reported at the use.
#define PAIR(a, b) ((a) + (b))

int main(void) {
  return PAIR(1);
}
