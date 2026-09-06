#include "x2c.x"

macro Expression $through_lisp(Expr $value) => ($(car (list $value)))
macro Expression $binding_name(Expr $value) => (
  $(x2c.binding.spelling $value)
)
macro Expression $prefix_names(Expr $value, Expr $values) => (
  $(car (list $values))
)

int main(void) {
  int value = 42;
  printf(
    "%s %d %d\n",
    $binding_name(value),
    $through_lisp(value),
    $prefix_names(value, 23)
  );
  return 0;
}
