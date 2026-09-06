#include "x2c.x"

static long identity(long value) {
  return value;
}

static Func lifted = identity;

void List.initialize(void) {
}
