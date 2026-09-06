#include "x2c.x"

typedef String (*StringCallback)(Var);
typedef String (*SourceCallback)(String);

static String source(String value) {
  return value;
}

static SourceCallback pointer = source;
static StringCallback callback =
  $x2c.callback.adapt(StringCallback, pointer);
