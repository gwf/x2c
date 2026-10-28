#include "x2c.x"
#include "meta.x"
meta static List make_main(void) {
  int number = (int) 0;
  List main_name = x2c_ident("main");
  return $!Unit{ int $main_name(void) { return 0; } };
}
macro Unit $go() { @make_main() }
$go();
