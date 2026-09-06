#include "x2c.x"

int main(void) {
  String value = %"ab";
  value[0]++;
  return 0;
}
