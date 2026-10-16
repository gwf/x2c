#include "x2c.x"
#include <stdio.h>

/* A type name in a macro body resolves where the expansion lands, in a
   `sizeof` operand, a cast, and `_Alignof` as in a declaration. A cast
   after `=>` is a cast, not a parenthesized legacy body. */
typedef int T;
macro Expression $size() => sizeof(T);
macro Expression $cast() => (T) 2.5;
macro Expression $called() => (T)(2.5);
macro Expression $align() => _Alignof(T);

int main(void) {
  typedef double T;
  printf("%d %g %g %d\n", (int) $size(), (double) $cast(), (double) $called(),
         (int) $align());
  return 0;
}
