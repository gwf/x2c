/* A struct under `#pragma pack` has no compile-time layout: C packs its
   fields, so natural alignment would misplace them. Packing that ends at the
   pop, or sits in an arm C never reaches, leaves a struct its natural
   layout. */

#include "x2c.x"

#pragma pack(push, 1)
struct MetaPacked { char tag; short value; };
#pragma pack(pop)

#ifdef _MSC_VER
#pragma pack(1)
#endif
struct MetaUnpacked { char tag; short value; };

meta int meta_unpacked_value(void) {
  struct MetaUnpacked unpacked = { .tag = 1, .value = 2 };
  return unpacked.value;
}

meta int meta_packed_value(void) {
  struct MetaPacked packed = { .tag = 1, .value = 2 };
  return packed.value;
}

int main(void) { return 0; }
