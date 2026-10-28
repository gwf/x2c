#include "bridge.x"
#include "b.x"
int main(void) {
  printf("%d %d %d %d %d %d\n", A, A_MACRO, $a_public(), B, B_MACRO, $b_public());
  printf("%d %d %d\n", $a_state(), $a_state(), $b_state());
  return 0;
}
