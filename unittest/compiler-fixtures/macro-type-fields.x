#include "x2c.x"
#include "macro-type-fields-include.h"
#include "macro-type-fields-import.x"
$imported_record(ReflectedImported);

macro Field $generated_field() {
  long $x2c_ident("generated");
}

meta static List same_fields(Type type, List expected, String message) {
  List actual = Type.fields(type);
  if (!actual.equal(expected))
    x2c_diagnostic_fail(message, %($(actual.repr())));
  return %();
}

macro Unit $check_record(Type $type) {
  @same_fields($type,
    %(("first" (int))
      ("second" (int))
      ("counts" ((dim ("3")) const unsigned long))
      ("name" (* const char))
      ("flags" ((bitfield ("3")) unsigned))
      ("generated" (long))),
    "record fields differ")
}

macro Unit $check_union(Type $type) {
  @same_fields($type, %(("integer" (int)) ("floating" (float))),
    "union fields differ")
}

macro Unit $check_included(Type $type) {
  @same_fields($type, %(("included" (short))), "included fields differ")
}

macro Expression $first(Expr $receiver) => $receiver.first;

typedef struct ReflectedRecord {
  int first, second;
  const unsigned long counts[3];
  const char *name;
  unsigned flags:3;
  int :2;
  $generated_field();
} ReflectedRecord;

typedef ReflectedRecord ReflectedAlias;

typedef union ReflectedUnion {
  int integer;
  float floating;
} ReflectedUnion;

$check_record(ReflectedAlias);
$check_union(ReflectedUnion);
$check_included(IncludedRecord);
$check_included(struct ReflectedImported);

int main(void) {
  ReflectedRecord record = { .first = 17 };
  ReflectedRecord *pointer = &record;
  printf("%d %d\n", $first(record), $first(pointer));
  return 0;
}
