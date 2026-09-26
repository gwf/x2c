#include "x2c.x"
$(import "meta-container-shared.xmacro")

int main(void) {
  Map result = $shared_result();
  return result.len();
}
