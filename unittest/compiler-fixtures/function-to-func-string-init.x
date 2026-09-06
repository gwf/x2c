#include "x2c.x"

static String identity(String value) {
  return value;
}

static Func lifted = identity;

void String.initialize(void) {
}
