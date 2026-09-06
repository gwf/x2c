#include "x2c.x"

macro Statement $bad() => {
  $(quote ((protocol bogus)))...
}

static void use_bad(void) {
  $bad();
}
