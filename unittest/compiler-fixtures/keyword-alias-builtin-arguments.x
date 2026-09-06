#include "x2c.x"
#include <stdlib.h>

keyword foreign $x2c.foreign.alias;

foreign(abs)
inline int aliased_absolute(int value);

int main(void) {
  printf("%d\n", aliased_absolute(-42));
  return 0;
}
