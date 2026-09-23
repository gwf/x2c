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

// Either arm's push is undone by the one pop after the group.
#ifdef __LP64__
#pragma pack(push, 8)
#else
#pragma pack(push, 4)
#endif
struct MetaWide { char tag; int value; };
#pragma pack(pop)
struct MetaLater { char tag; int value; };

// A pop under the same guard as its push ends the packing.
#ifdef META_PACK_GUARD
#pragma pack(push, 1)
#endif
struct MetaGuarded { char tag; int value; };
#ifdef META_PACK_GUARD
#pragma pack(pop)
#endif
struct MetaAfterGuard { char tag; int value; };

meta int meta_unpacked_value(void) {
  struct MetaUnpacked unpacked = { .tag = 1, .value = 2 };
  return unpacked.value;
}

meta int meta_later_value(void) {
  struct MetaLater later = { .tag = 1, .value = 2 };
  return later.value;
}

meta int meta_after_guard_value(void) {
  struct MetaAfterGuard after = { .tag = 1, .value = 2 };
  return after.value;
}

meta int meta_packed_value(void) {
  struct MetaPacked packed = { .tag = 1, .value = 2 };
  return packed.value;
}

int main(void) { return 0; }
