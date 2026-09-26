/* A shared builder that queries the compiler keeps its callers
   compile-time only, including after a unit resets its parsing state. */
#include "x2c.x"
#include "meta.x"

$(import "meta-builder-compiler-only.xmacro")

int main(void) {
  return wrap(%()).len();
}
