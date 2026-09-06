#include "x2c.x"
#include "include-recursion-a.h"
#include "include-recursion-b.h"

int main(void) {
  RecursionPair pair = recursion_pair(21);
  printf("%d\n", pair.value);
  return pair.value == 42 ? 0 : 1;
}
