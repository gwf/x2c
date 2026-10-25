#include "x2c.x"
meta static List reference_rows(void) {
  return %(
    (declare (int) (bindings (bind ("alias") (&))))
    (return (int) (expr (int) (literal (int) "0"))));
}
macro Unit $construct() {
  static int $x2c_ident("constructed")(void) {
    @reference_rows()
  }
}
$construct();
int main(void) { return 0; }
