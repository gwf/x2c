#include "x2c.x"
#include "meta.x"

meta static List _call(String name) =>
  x2c_expr_call(x2c_expr_ident(%(%"$name")), NULL);

macro Expression $call() => $_call("abs");

int value = $call();
