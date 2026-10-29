#include "x2c.x"

// An error in an expansion is reported at the macro use, with a note that
// names the macro and where it is defined.
#define HALF(x) (x /)

int main(void) {
  int value = HALF(4);
  return value;
}
