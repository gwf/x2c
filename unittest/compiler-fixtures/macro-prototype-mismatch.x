#include "x2c.x"

macro Unit $define_increment() {
  int $x2c_ident("generated_increment")(int value) {
    return value + 1;
  }
}

long generated_increment(long);
$define_increment();
