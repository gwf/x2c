#include "x2c.x"

$(import "meta-iterator-user-kernel.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $user_kernel_probe(0),
         user_kernel_probe(argc - 1));
  return 0;
}
