#include "x2c.x"

$(import "meta-equality-guards.xmacro")

int main(void) {
  printf("scalar %d %d %d\n", $(int_guard 0), $(int_guard 0.0),
         $(int_guard 2));
  printf("list %d %d\n", $(list_guard nil), $(list_guard '(1)));
  printf("equal %d %d %d\n", $(list_equal nil nil),
         $(list_equal '(1) '(1)), $(list_equal '(1) '(2)));
  printf("effects %d\n", $(equality_effect));
}
