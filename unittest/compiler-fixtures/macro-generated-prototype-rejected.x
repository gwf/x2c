#include "x2c.x"

macro Unit $declare_generated() {
  int $x2c_ident("generated_function")(int);
}

macro Unit $define_generated() {
  int $x2c_ident("generated_function")(int value) {
    return value;
  }
}

$declare_generated();
$define_generated();
