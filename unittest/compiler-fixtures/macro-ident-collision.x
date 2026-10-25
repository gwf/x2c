#include "x2c.x"

static int generated_collision = 1;

macro Unit $define_collision() {
  static int $x2c_ident("generated_collision") = 2;
}

$define_collision();
