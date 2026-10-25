#include "x2c.x"

meta static List forged_syntax(void) =>
  %(expr () (ident (binding 999 "missing")));
macro Expression $forged() => $forged_syntax();

int value = $forged();
