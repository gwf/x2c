#include "x2c.x"

// A `meta` function runs as native code, so a compile-time call nests as
// deep as the same call at run time.

$(import "meta-call-depth.xmacro")

int main(void) {
  printf("%d\n", $md_deep(4000));
  return 0;
}
