#include "x2c.x"

int main(void) {
  Map values = %{1: "two", "three": 4};
  Map first = %{}, second = %{};
  size_t width = values.entries.block().width;
  printf(
    "%zu %d %s %ld %d\n", width, width == 2 * sizeof(Var),
    values[1].string(), values["three"].integer(), first !== second
  );
  return 0;
}
