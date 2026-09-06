#include "typed-array.x"

int main(void) {
  ArrayInt values = %[2, 4, 6];
  int total = 0;
  foreach(int value, values) total += value;
  printf("%d\n", total);
  return total == 12 ? 0 : 1;
}
