/* Collection reads a quoted header's `#pragma pack` and attributes, so a
   header struct that C packs or realigns has no compile-time layout. Other
   attributes leave a struct its natural layout. The `--system-headers` form
   is meta-system-header-packed. */

#include "meta-system-header-packed/packed.h"

meta int header_pragma_value(void) {
  struct HeaderPragma value = { .value = 1 };
  return value.value;
}

meta int header_packed_value(void) {
  struct HeaderPacked value = { .value = 2 };
  return value.value;
}

meta int header_aligned_value(void) {
  struct HeaderAligned value = { .value = 3 };
  return value.value;
}

meta int header_plain_value(void) {
  struct HeaderPlain value = { .value = 4 };
  return value.value;
}

int main(void) { return 0; }
