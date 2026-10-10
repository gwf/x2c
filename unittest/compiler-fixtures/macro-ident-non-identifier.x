#include "x2c.x"
#include "meta.x"

meta static List _call(String name) =>
  %(expr () (call (expr () (ident (%"$name"))) (args)));

macro Expression $call() => $_call("abs");

int value = $call();
