/* A shared builder that queries the compiler keeps its callers
   compile-time only, including after a unit resets its parsing state. */
#include "x2c.x"
#include "meta.x"

meta static List field(List receiver) => x2c_expr_field(receiver, "a");
meta static List wrap(List receiver) => field(receiver);

int main(void) {
  return wrap(%()).len();
}
