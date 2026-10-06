/* A public prototype names an included type, so the generated header
   includes its provider and compiles on its own. */

int a_value(void);
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
