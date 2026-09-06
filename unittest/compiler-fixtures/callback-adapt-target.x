#include "x2c.x"

typedef String (*StringCallback)(Var);

static StringCallback target;
static StringCallback callback =
  $x2c.callback.adapt(target, String.str);
