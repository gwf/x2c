#include "x2c.x"

macro Stmt $bad() {
  $(quote ((protocol bogus)))...
}

static void use_bad(void) {
  $bad();
}
