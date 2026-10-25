#include "x2c.x"

macro Expression $reject(Expr $value) =>
  $x2c_diagnostic_fail("chosen compile-time failure",
                      %("first note" "second note"));

int value = $reject(1);
