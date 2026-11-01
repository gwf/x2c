#include <stdio.h>

__attribute__((unused)) typedef int Count;
typedef __attribute__((unused)) Count Other;
__attribute__((aligned(16))) typedef int Aligned;

int main(void) {
  __attribute__((unused)) typedef Count Local;
  Count first = 3;
  Other second = 4;
  Local third = 5;
  printf("%d %d %d %zu\n", first, second, third, _Alignof(Aligned));
  return 0;
}
