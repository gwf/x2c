#include "x2c.x"

int main(void) {
  List input = %(tag 1);
  match (input) {
    case %(!or (tag ?value) (tag none)):
      return 1;
  }
  return 0;
}
