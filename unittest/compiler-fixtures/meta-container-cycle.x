#include "x2c.x"
$(import "meta-container-cycle.xmacro")

int main(void) {
  Array result = $cyclic_result();
  return result.len();
}
