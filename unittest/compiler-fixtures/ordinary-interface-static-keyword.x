#include "ordinary-interface-provider.x"

static int private_type(int value) => 2 * value;

int main(void) {
  printf("%d\n", private_type(21));
  return 0;
}
