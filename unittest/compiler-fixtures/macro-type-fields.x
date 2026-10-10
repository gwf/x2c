#include "x2c.x"
#include "macro-type-fields-include.h"
#include "macro-type-fields-import.x"
$imported_record(ReflectedImported);

macro Field $generated_field() {
  long $(x2c.ident "generated");
}

macro Unit $check_record(Type $type) {
  @(let ((actual (Type.fields $type)))
     (if (equal? actual
           '(("first" (int))
             ("second" (int))
             ("counts" ((dim ("3")) const unsigned long))
             ("name" (* const char))
             ("flags" ((bitfield ("3")) unsigned))
             ("generated" (long))))
         nil
         (x2c.diagnostic.fail "record fields differ" (list (repr actual)))))
}

macro Unit $check_union(Type $type) {
  @(let ((actual (Type.fields $type)))
     (if (equal? actual
           '(("integer" (int)) ("floating" (float))))
         nil
         (x2c.diagnostic.fail "union fields differ" (list (repr actual)))))
}

macro Unit $check_included(Type $type) {
  @(let ((actual (Type.fields $type)))
     (if (equal? actual '(("included" (short))))
         nil
         (x2c.diagnostic.fail "included fields differ"
                              (list (repr actual)))))
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
