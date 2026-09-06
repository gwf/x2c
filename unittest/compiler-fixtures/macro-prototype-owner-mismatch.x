#include "x2c.x"

typedef int Left;
typedef int Left_Right;

macro Unit $define_method(
  Type $owner, Param $parameter
) => {
  int $owner.Right_value($parameter) {
    return 0;
  }
}

int Left_Right.value(int);
$define_method(Left, int value);
