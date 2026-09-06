#include "x2c.x"

// A nonzero integer never makes a pointer, so the match subject below has
// no conversion to List.  Before this was diagnosed the compiler exited 0
// and emitted `List _x2c_match_expr = 42;`, which the C compiler rejects.
int main(void) {
  match (42) {
    case %( ?x ): return 1;
  }
  return 0;
}
