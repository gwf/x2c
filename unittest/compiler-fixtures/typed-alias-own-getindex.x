#include "x2c.x"

typedef List ListInt;

int ListInt.getindex(ListInt values, int index) {
  (void) values;
  return 40 + index;
}

int main(void) {
  ListInt values = NULL;
  int value = values[2];
  printf("%d\n", value);
  return 0;
}
