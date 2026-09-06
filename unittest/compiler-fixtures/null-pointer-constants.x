#include "x2c.x"

// The companion to nonzero-integer-to-pointer and integer-variable-to-
// pointer: C11 6.3.2.3p3 makes a null pointer constant an integer
// *constant expression* with value zero, not merely the token 0.  Every
// spelling below is therefore a null pointer constant and must still
// convert silently.  This fixture is what stops that guard from being
// widened into something that rejects valid C.
//
// The last three matter most.  x2c does not fold constants, so (1 - 1), a
// zero-valued enumeration constant, and '\0' cannot be shown to be zero
// without evaluating or resolving them.  A widening that exempted only
// zero *literals* would reject all three while every other case here kept
// passing, so they are pinned explicitly.

enum NullConstants { ZERO = 0 };

int main(void) {
  List a = 0, b = 0L, c = NULL, d = (0), e = 0x0, f = 0U;
  Map  g = 0;
  String h = 0;
  List i = (1 - 1), j = ZERO, k = '\0';
  int zeros = !a + !b + !c + !d + !e + !f + !g + !h + !i + !j + !k;
  printf("null pointer constants: %d\n", zeros);
  return 0;
}
