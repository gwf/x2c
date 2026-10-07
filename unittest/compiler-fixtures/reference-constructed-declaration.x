#include "x2c.x"
macro Unit $construct() {
  static int $(x2c.ident "constructed")(void) {
    @(quote (
      (declare (int) (bindings (bind ("alias") (&))))
      (return (int) (expr (int) (literal (int) "0")))
    ))
  }
}
$construct();
int main(void) { return 0; }
