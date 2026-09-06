#include "x2c.x"

int main(void) {
  int value = 42;
  List braced = %(${value});
  List rejected = %($(value));
  return braced != %(42) || rejected != braced;
}
