#include "x2c.x"

meta static List forged_binding(List value) {
  match (value) {
    case %(expr ? (ident (binding ?id ?))): return %(binding $id "forged");
  }
  return %();
}

macro Expression $spelling(Expr $value) =>
  $Code.binding_spelling($forged_binding($value));

int value = $spelling(value);
