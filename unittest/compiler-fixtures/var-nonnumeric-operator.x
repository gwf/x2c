#include "x2c.x"

int main(void) {
  Var value = 1;
  String text = %"text";
  Var invalid = value * text;
  return invalid.truthy();
}
