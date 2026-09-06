#include "x2c.x"
#include <stdio.h>

int main(void) {
  List input = %(node 5 tail more);
  match (input) {
    case %(node ?value *rest):
      printf("%d %d\n", value.int(), rest.len());
  }
  return 0;
}
