#include "x2c.x"
#include "array.x"

struct Counter { int value; };

int main(void) {
  struct Counter loop = {0};
  loop.value = 7;
  int keyword = loop.value;
  printf("%d\n", keyword);
  return 0;
}
