#include "x2c.x"

typedef String (*StringCallback)(Var);

static StringCallback callback =
  $x2c.callback.adapt(StringCallback, String.missing);
