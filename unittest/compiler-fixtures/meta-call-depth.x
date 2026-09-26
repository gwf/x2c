#include "x2c.x"

// A `meta` function runs as native code, so a compile-time call nests as
// deep as the same call at run time.

meta static int md_deep(int n) { return n <= 0 ? 0 : 1 + md_deep(n - 1); }

int main(void) {
  printf("%d\n", $md_deep(4000));
  return 0;
}
