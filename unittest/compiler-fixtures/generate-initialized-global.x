/* A public object's header declaration omits its initializer, so an
   initializer that names a static object keeps the object public. */
#include "generate-initialized-global-counter.x"

int main(void) {
  printf("%d\n", *current);
  return 0;
}
