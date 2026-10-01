/* A public prototype below `#pragma private` that names a type from a
   private include moves that include to the header, so the header compiles
   on its own. */

int a_value(void);
#pragma private
#include "private-include-header-types.x"

Hidden a_make(int n) {
  Hidden h = {n};
  return h;
}

int a_value(void) => a_make(3).n;

int main(void) {
  printf("%d\n", a_value());
  return 0;
}
