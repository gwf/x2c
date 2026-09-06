#include "x2c.x"

macro Expression $reject(Expr $value) => (
  $(x2c.diagnostic.fail "chosen compile-time failure"
                        (list "first note" "second note"))
)

int value = $reject(1);
