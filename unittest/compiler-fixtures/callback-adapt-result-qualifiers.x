#include "x2c.x"

/* A generated callback must not expose a const result as writable. */
typedef char *(*Namer)(Var);

static const char *name_of(Symbol value) {
  return value == <yes> ? "yes" : "no";
}

static Namer namer = $x2c.callback.adapt(Namer, name_of);
