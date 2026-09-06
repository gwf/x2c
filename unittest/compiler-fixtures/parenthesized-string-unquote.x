#include "x2c.x"

int main(void) {
  int value = 42;
  String braced = %"${value}";
  String rejected = %"$(value)";
  return rejected != braced;
}
