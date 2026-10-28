#include "x2c.x"
#include "meta.x"
meta static List gen(void) {
  List fn = x2c_ident("show");
  return $!Unit{ int $fn(int value) { return value + zzz; } };
}
macro Unit $gen.it() { @gen() }
$gen.it();
int main(void) { printf("%d\n", show(1)); return 0; }
