#include "x2c.x"

int main(void) {
  Array destination = %[1];
  Map source = %{};
  destination[0] += source[%"missing"];
  return 0;
}
