/*  comptime-declines-local-address-array.x -- a meta function returns its
    own local array

    The array decays to the address of its first element, which the call
    frees when it returns, so the definition is rejected at the return.
*/

#include "x2c.x"

meta static int *numbers(int seed) {
  int values[4];
  values[0] = seed;
  return values;
}

int main(void) { return 0; }
