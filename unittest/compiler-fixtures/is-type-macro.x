#include "x2c.x"
#include <stdio.h>

macro Expression $is_type(Expr $value, Type $T) => ($value is $T)
macro Expression $is_tag(Expr $value, Expr $tag) => ($value is $tag)
macro Expression $is_not_type(Expr $value, Type $T) => ($value is not $T)
macro Expression $is_not_tag(Expr $value, Expr $tag) => ($value is not $tag)
macro Expression $is_pointer(Expr $value, Type $T) => (
  $value is ($T *)
)

int main(void) {
  int number = 1, *pointer = &number;
  Var scalar = number, pointer_value = pointer;
  int ok =
    $is_type(scalar, int) &&
    $is_tag(scalar, <i32>) &&
    $is_not_type(scalar, double) &&
    $is_not_tag(scalar, <f64>) &&
    $is_type(pointer_value, int *) &&
    $is_pointer(pointer_value, int);
  printf("%d\n", ok);
  return ok ? 0 : 1;
}
