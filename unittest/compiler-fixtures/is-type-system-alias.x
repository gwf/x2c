#include "x2c.x"
#include <stdint.h>

int main(void) {
  Var short_value = (uint16_t) 7, wide_value = (uint64_t) 7;
  int ok = short_value is uint16_t && short_value is u16 &&
           wide_value is uint64_t && wide_value is u64;
  printf("%d\n", ok);
  return !ok;
}
