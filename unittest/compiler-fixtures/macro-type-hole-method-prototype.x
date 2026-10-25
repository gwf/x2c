#include "x2c.x"

typedef int Box;

meta static List arguments_of(List parameter) =>
  Code.arguments(%($parameter));

macro Unit $box(
  Type $type, Literal $tag, Param $parameter
) {
  inline Var $type.var($parameter) {
    return Var.new(
      $tag, @arguments_of($parameter)
    );
  }
}

Var Box.var(Box);
$box(Box, <i32>, Box value);

int main(void) {
  printf("%d\n", Box.var(42));
  return 0;
}
