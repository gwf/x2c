#include "x2c.x"

$(import "meta-func-error-wrong-value-type.xmacro")

int main(void) {
  (void) $wrong_value_type(1);
  return 0;
}
