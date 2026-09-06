#include "x2c.x"

typedef int (*VariadicCallback)(Var, ...);

static int source(String format, ...) {
  return format.len();
}

static VariadicCallback callback =
  $x2c.callback.adapt(VariadicCallback, source);
