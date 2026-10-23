#include "x2c.x"

typedef int Ints[2];

int main(void) {
  const Ints values = { 1, 2 };
  auto pointer = values;
  printf("%d\n", pointer[0]);
  return 0;
}
