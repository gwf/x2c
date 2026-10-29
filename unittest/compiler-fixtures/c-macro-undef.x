#include "x2c.x"

// After `#undef`, the name is an ordinary identifier again.
#define value 41

int before(void) { return value; }

#undef value
int value = 1;

int main(void) {
  printf("%d %d\n", before(), value);
  return 0;
}
