#include "x2c.x"

void install_binding(Lisp lisp) {
  $lisp.install(lisp, missing);
}
