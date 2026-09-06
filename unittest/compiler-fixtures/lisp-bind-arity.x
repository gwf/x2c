#include "x2c.x"

static int too_many(
  int a, int b, int c, int d, int e, int f, int g, int h, int i) {
  return a + b + c + d + e + f + g + h + i;
}

void install_binding(Lisp lisp) {
  $lisp.bind(lisp, "too-many", too_many);
}
