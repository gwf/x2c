#include "x2c.x"

// A macro whose expansion supplies declarations and statements expands
// before parsing, so an X-macro list declares the fields and prints them.
#define FIELDS(X) X(alpha) X(beta)
#define DECL(n) int n;
#define PRINT(n) printf(#n "=%d\n", s.n);

struct Pair { FIELDS(DECL) };

int main(void) {
  struct Pair s = {1, 2};
  FIELDS(PRINT)
  return 0;
}
