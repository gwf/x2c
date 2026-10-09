#include "x2c.x"
#include "type.x"

meta int pointer_type(Type type) => type.canonicalize().is_pointer();
meta int integer_expression(Code code) => code.type() == $!Type{int};

meta int constant_three(Code code) => code.value() == 3;
meta int macro_pattern(Code code) {
  Macro shape = code.value();
  List pattern = shape.pattern(%(?left ?right));
  return !!$!int{1 + 2}.match(pattern);
}

macro Expression $sum(Expr $left, Expr $right) => $left + $right;
macro Expression $three(Expr $code) => $constant_three($code);
macro Expression $pattern(Expr $code) => $macro_pattern($code);
macro Expression $pointer(Type $type) => $pointer_type($type);
macro Expression $integer(Expr $value) => $integer_expression($value);

int main(void) {
  Type qualified = $!Type{int * const};
  Type pointer = qualified.canonicalize();
  Type integer = $!Type{int};
  printf("%d %d %d\n", qualified.is_pointer(), pointer.is_pointer(),
         pointer.dereference() == integer);
  printf("%d %d\n", $pointer(int * const), $pointer(int));
  printf("%d %d\n", $three(3), $pattern($sum));
  int value = 3;
  printf("%d %d\n", $integer(value + 1), $integer(1.5));
  {
    double value = 3;
    printf("%d\n", $integer(value));
  }
  return 0;
}
