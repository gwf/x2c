#include "x2c.x"

$(import "meta-func-error-wrong-reference-type.xmacro")

int main(void) {
  (void) $wrong_reference_type(1);
  return 0;
}
