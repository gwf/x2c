#include "x2c.x"

macro Decorator $fixture.tag(
  Function $target,
  Expr $value
) => {
  printf("%d ", $value);
  $(x2c.function.body $target)...
}

macro Decorator $fixture.annotate_field(
  Field $target,
  Name $extra
) => {
  $target
  int $extra;
}

macro Decorator $fixture.annotate_unit(
  Unit $target,
  Name $extra
) => {
  $target
  static int $extra = 1;
}

keyword tagged $fixture.tag;
keyword annotated_field $fixture.annotate_field;
keyword annotated_unit $fixture.annotate_unit;

$fixture.annotate_unit(direct_unit_extra)
static int direct_unit_target = 2;

annotated_unit(aliased_unit_extra)
static int aliased_unit_target = 3;

typedef struct DirectFields {
  $fixture.annotate_field(direct_extra)
  int direct;
} DirectFields;

typedef struct AliasedFields {
  annotated_field(aliased_extra)
  int aliased;
} AliasedFields;

$fixture.tag(20)
static int direct(int value) {
  return value + 1;
}

tagged(22)
static int aliased(int value) {
  return value + 1;
}

int main(void) {
  DirectFields direct_fields = { 4, 5 };
  AliasedFields aliased_fields = { 6, 7 };
  printf(
    "%d %d %d\n",
    direct(20) + aliased(20),
    direct_unit_target + direct_unit_extra +
      aliased_unit_target + aliased_unit_extra,
    direct_fields.direct + direct_fields.direct_extra +
      aliased_fields.aliased + aliased_fields.aliased_extra
  );
  return 0;
}
