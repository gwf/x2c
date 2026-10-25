/* Native and Var comparisons use C conversions. */
#include "x2c.x"

meta static int identity(int value) => value;

int main(void) {
  long long precise = 9007199254740993LL;
  printf("less %d %d\n", $identity(-1 < 1U), -1 < 1U);
  printf("equal %d %d\n", $identity(-1 == 0xFFFFFFFFU), -1 == 0xFFFFFFFFU);
  printf("different %d %d\n", $identity(-1 != 0xFFFFFFFFU), -1 != 0xFFFFFFFFU);
  printf("greater %d %d\n", $identity(1U > -1), 1U > -1);
  printf("at-most %d %d\n",
    $identity(9007199254740993LL <= 9007199254740992.0),
    precise <= 9007199254740992.0);
  printf("at-least %d %d\n",
    $identity(9007199254740993LL >= 9007199254740992.0),
    precise >= 9007199254740992.0);
  printf("rounded %d %d\n",
    $identity(9007199254740993LL == 9007199254740992.0),
    precise == 9007199254740992.0);
  return 0;
}
