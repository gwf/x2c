#include "x2c.x"

macro Expression $constructed() =>
  $(x2c.literal.string (Code.source_text '(expr (int) (literal (int) "1"))));

String value = $constructed();
