#include "x2c.x"

#if ~0U > 0
int selected(void) => 1;
#else
int selected(void) => 2;
#endif
#if 0xffffffffffffffffUL > 0
int largest(void) => 3;
#else
int largest(void) => 4;
#endif

int main(void) {
  printf("%d %d\n", selected(), largest());
  return 0;
}
