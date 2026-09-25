/* method-extra-arguments.x -- a method call supplies too many arguments. */
#include "x2c.x"

int main(void) {
  List items = ["a, b", "c, d"];
  items.last().split(", ");
  return 0;
}
