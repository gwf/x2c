#include "x2c.x"

macro Unit $define_read() {
  int $x2c_ident("generated_read")(int *value) {
    return *value;
  }
}

int generated_read(const int *);
$define_read();
