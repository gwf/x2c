#include "x2c.x"
#include "typed-array.x"

int main(void) {
  ArrayDbl ratios = ArrayDbl.new();
  ratios.push(1.5);
  ArrayInt counts = ratios;
  (void) counts;
  return 0;
}
