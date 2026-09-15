#include "x2c.x"

/* A local assigned inside `try` is volatile, so the address `$let` saves
   points at a volatile object. */

int main(void) {
  int outer = 1;
  try {
    outer = 2;
    $let(outer, 5) printf("inside %d\n", outer);
  }
  finally printf("after %d\n", outer);
  return 0;
}
