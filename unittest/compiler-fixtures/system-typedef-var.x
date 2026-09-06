#include "x2c.x"
#include <stddef.h>
#include <stdint.h>

int main(void) {
  size_t n = 42;
  Var v = n;
  size_t back = v;
  uint32_t u = 7;
  Var w = u;
  uint32_t uback = w;
  ptrdiff_t d = -3;
  Var e = d;
  ptrdiff_t dback = e;
  // Var.uint reads the u32 payload this uint32_t seed boxed.  Reader
  // conversion policy for other tags is a runtime question, pinned in
  // unittest/test-var.x rather than in this fixture's golden output.
  printf("%d %d %d %d\n", (int) back, (int) uback, (int) dback,
         (int) w.uint());
  return 0;
}
