/* A switch rule whose replacement holds a new switch lowers it once. */

#include "x2c.x"
#include <stdio.h>

static int counted = 0;

#include "rewrite-switch-replacement-defs.x"

static int pick(int n) {
  switch (n) {
    case 1:
      switch (n + 1) {
        case 2: return 12;
      }
      return 10;
    case 2: return 20;
  }
  return 0;
}

int main(void) {
  int one = pick(1), first = counted;
  int two = pick(2), second = counted;
  int other = pick(3);
  printf("%d %d %d %d %d %d\n", one, first, two, second, other, counted);
  return 0;
}
