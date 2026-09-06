#include "x2c.x"

macro Unit $define_repeat(Literal $value) => {
  static int $(x2c.ident "generated_repeat") = $value;
}

$define_repeat(1);
$define_repeat(2);
