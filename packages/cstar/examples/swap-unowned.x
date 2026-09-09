/*  swap-unowned.x -- swap without the second cell's ownership.

    The ghost parameters name the values the caller owns on entry. The
    contract states the ownership the function needs and the ownership it
    returns; `swap-unowned.x` asks for only one of the two cells and cannot
    be proved.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

#include <stdio.h>

$cstar.verify_with(
  "a_v:int, b_v:int",
  "data_at a Tint a_v",
  "data_at a Tint b_v ** data_at b Tint a_v"
)
static void swap(int *a, int *b) {
  int t = *a;
  *a = *b;
  *b = t;
}

int main(void) {
  int left = 3, right = 8;
  swap(&left, &right);
  printf("%d %d\n", left, right);
  return 0;
}
