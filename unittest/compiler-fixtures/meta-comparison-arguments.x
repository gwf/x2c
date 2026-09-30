/* Native comparison arguments use C conversions; Var compares exactly. */
#include "x2c.x"

meta static int identity(int value) => value;

int main(void) {
  printf("less %d %d\n", $identity(-1 < 1U), -1 < 1U);
  printf("equal %d %d\n", $identity(-1 == 0xFFFFFFFFU), -1 == 0xFFFFFFFFU);
  printf("different %d %d\n", $identity(-1 != 0xFFFFFFFFU), -1 != 0xFFFFFFFFU);
  printf("greater %d %d\n", $identity(1U > -1), 1U > -1);
  printf("at-most %d %d\n",
    $identity(9007199254740993LL <= 9007199254740992.0),
    9007199254740993LL <= 9007199254740992.0);
  printf("at-least %d %d\n",
    $identity(9007199254740993LL >= 9007199254740992.0),
    9007199254740993LL >= 9007199254740992.0);
  printf("rounded %d %d\n",
    $identity(9007199254740993LL == 9007199254740992.0),
    9007199254740993LL == 9007199254740992.0);
  printf("dynamic %d %d\n", $(if (< -1 1) 1 0), (Var) -1 < (Var) 1U);
  return 0;
}
