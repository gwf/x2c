#include "x2c.x"

macro Unit $define_increment() {
  int $x2c_ident("generated_increment")(
    int $x2c_ident("value")
  ) {
    if ($x2c_ident("value") < 0)
      raise %(bad-arg (operation "generated_increment"));
    return $x2c_ident("value") + 1;
  }
}

int generated_increment(int value);
$define_increment();

int main(void) {
  printf("%d\n", generated_increment(41));
  return 0;
}
