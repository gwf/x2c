#include "x2c.x"

typedef void (*VoidCallback)(Var);

static void consume(String value) {
  (void) value;
}

static VoidCallback callback =
  $x2c.callback.adapt(VoidCallback, consume);
