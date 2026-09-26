/*  comptime-declines-local-address-static.x -- a meta function stores the
    address of its own local into a `meta static`

    The static outlives the call, and the call frees the local when it
    returns, so the definition is rejected at the store.
*/

#include "x2c.x"

meta static int *saved = NULL;

meta static int remember(int seed) {
  int value = seed;
  saved = &value;
  return *saved;
}

int main(void) { return 0; }
