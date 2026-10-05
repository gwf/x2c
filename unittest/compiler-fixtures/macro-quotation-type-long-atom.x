#include "x2c.x"
#include "meta.x"

/* Long Atoms are not String-backed type names either. */
typedef List ExtremelyLongCamelCaseCaptureType;
meta static List typed_list(List value) {
  Type type = %(ExtremelyLongCamelCaseCaptureType);
  return $!($type){ $value };
}
macro Expression $list_of(Expr $value) => $typed_list($value);

int main(void) {
  ExtremelyLongCamelCaseCaptureType values = $list_of(%(1 2));
  return values.len() != 2;
}
