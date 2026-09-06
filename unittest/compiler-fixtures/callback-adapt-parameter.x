#include "x2c.x"

typedef String (*IntCallback)(int);

static String source(String value) {
  return value;
}

static IntCallback callback =
  $x2c.callback.adapt(IntCallback, source);
