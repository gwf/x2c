#include "x2c.x"

int main(void) {
  Var first = 0, second = 0;
  List copy = ({
    (first, second) = 12;
  });
  return 0;
}
