#include "x2c.x"

macro Expression $constructed() =>
  $Code.source_text(%(expr (int) (literal (int) "1")));

String value = $constructed();
