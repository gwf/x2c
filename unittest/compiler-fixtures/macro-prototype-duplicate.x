#include "x2c.x"

macro Unit $define_increment() => {
  int $(x2c.ident "generated_increment")(int value) {
    return value + 1;
  }
}

int generated_increment(int);
$define_increment();
$define_increment();
