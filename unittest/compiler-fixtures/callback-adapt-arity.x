#include "x2c.x"

typedef String (*StringCallback)(Var);

static String pair(String left, String right) {
  return left ? left : right;
}

static StringCallback callback =
  $x2c.callback.adapt(StringCallback, pair);
