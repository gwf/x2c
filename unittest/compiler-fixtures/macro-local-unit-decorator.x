#include "x2c.x"

static void invalid_local_macro(void) {
  macro Decorator decorate(Unit $target) => {
    $target
  }
}
