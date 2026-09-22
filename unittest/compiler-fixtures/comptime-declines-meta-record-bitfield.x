/* A struct with a bitfield has no compile-time layout: where its bits sit
   is a property of the C ABI. */

#include "x2c.x"

struct MetaBits { unsigned value : 3; };

meta int meta_bits_value(void) {
  struct MetaBits bits = { .value = 2 };
  return bits.value;
}

int main(void) { return 0; }
