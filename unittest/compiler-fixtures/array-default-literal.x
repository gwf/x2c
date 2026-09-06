#include "x2c.x"

int main(void) {
  Array values = %[1, "two"];
  printf(
    "%zu %d %s\n", values.width, values[0].int(), values[1].string()
  );
  return 0;
}
