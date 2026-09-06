#include "x2c.x"

static void invalid_local_macro(void) {
  macro Decorator decorate(Function $target) => {
    $(x2c.function.body $target)...
  }
}
