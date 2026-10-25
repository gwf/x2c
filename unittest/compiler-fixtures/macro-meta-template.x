#include "x2c.x"

meta static List same(List value) => value;

macro Expression $through_meta(Expr $value) => $same($value);
macro Expression $binding_name(Expr $value) =>
  $Code.binding_spelling($value);
macro Expression $prefix_names(Expr $value, Expr $values) =>
  $same($values);

int main(void) {
  int value = 42;
  printf(
    "%s %d %d\n",
    $binding_name(value),
    $through_meta(value),
    $prefix_names(value, 23)
  );
  return 0;
}
