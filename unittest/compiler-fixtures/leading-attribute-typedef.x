#include <stdio.h>

__attribute__((unused)) typedef int Count;
typedef __attribute__((unused)) Count Other;
__attribute__((aligned(16))) typedef int Aligned;
#define AL16 __attribute__((aligned(16)))
AL16 typedef int MacroAligned;

int main(void) {
  __attribute__((unused)) typedef Count Local;
  Count first = 3;
  Other second = 4;
  Local third = 5;
  printf("%d %d %d %zu %zu\n", first, second, third, _Alignof(Aligned),
         _Alignof(MacroAligned));
  return 0;
}
