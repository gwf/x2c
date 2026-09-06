#include "x2c.x"

typedef String (*StringCallback)(Var);

static int length(String value) {
  return value.len();
}

static StringCallback callback =
  $x2c.callback.adapt(StringCallback, length);
