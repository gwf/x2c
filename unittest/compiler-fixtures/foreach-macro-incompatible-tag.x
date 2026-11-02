#include "x2c.x"

struct Pair {
  int value;
};

int main(void) {
  List values = %(1 2 3);
  foreach (struct Pair pair in values) (void) pair;
  return 0;
}
