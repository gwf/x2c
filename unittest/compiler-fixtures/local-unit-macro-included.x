// An including unit sees the method a Unit macro generates in the file
// that defines and invokes the macro, with its return type.
#include "x2c.x"
#include "local-unit-macro-included/scale.x"

int main(void) {
  int n = 21;
  printf("%d %d\n", n.twice(), twice_label(7).len());
  return 0;
}
