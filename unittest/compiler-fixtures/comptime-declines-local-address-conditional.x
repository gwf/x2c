/*  comptime-declines-local-address-conditional.x -- one arm of a
    conditional in a meta function is the address of its own local

    Either arm can be the result, so the definition is rejected at the
    return even though the other arm is the caller's pointer.
*/

#include "x2c.x"

meta static int *either(int flag, int *other) {
  int value = flag;
  return flag ? other : &value;
}

int main(void) { return 0; }
