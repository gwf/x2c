#include "x2c.x"

$lisp.binding(sample, "first")
static int first(int value) {
  return value;
}

void install_binding(Lisp lisp) {
  $lisp.install(lisp, sample);
}

$lisp.binding(sample, "late")
static int late(int value) {
  return value;
}
