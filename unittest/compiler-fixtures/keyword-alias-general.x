#include "x2c.x"

$(import "keyword-alias-general-import.xmacro")

static int add(int left, int right) {
  return left + right;
}

static int forty_two(void) {
  return 42;
}

static int identity(int value) {
  return value;
}

macro Expression $fixture.call(Expr $callee, Expr $arguments...) => (
  $callee($arguments...)
)

macro Statement $fixture.swap(Expr $left, Expr $right) using $temporary => {
  $(x2c.syntax.type $left) $temporary = $left;
  $left = $right;
  $right = $temporary;
}

macro Field $fixture.field(Name $name) => {
  int $name;
}

macro Enumerator $fixture.enumerator(Name $name, Literal $value) => {
  $name = $value
}

macro Unit $fixture.define(Name $name, Literal $value) => {
  static int $name(void) {
    return $value;
  }
}

macro Decorator $fixture.range(
  Block $body,
  Name $index,
  Expr $start,
  Expr $stop
) using $begin, $end => {
  {
    int $begin = $start, $end = $stop;
    for (int $index = $begin; $index < $end; $index++) $body
  }
}

macro Decorator $fixture.invoke(
  Expr $target,
  Expr $arguments...
) => ($target($arguments...))

keyword call $fixture.call;
keyword swap $fixture.swap;
keyword field $fixture.field;
keyword enumerator $fixture.enumerator;
keyword define $fixture.define;
keyword imported_type $fixture.imported_type;
keyword range $fixture.range;
keyword invoke $fixture.invoke;

imported_type(ImportedValue);

$fixture.define(direct_value, 5);
define(aliased_value, 7);

typedef struct AliasRecord {
  $fixture.field(direct_field);
  field(aliased_field);
} AliasRecord;

typedef enum AliasEnumerator {
  $fixture.enumerator(DIRECT_ENUMERATOR, 11),
  enumerator(ALIASED_ENUMERATOR, 13)
} AliasEnumerator;

int main(void) {
  AliasRecord record = { 17, 19 };
  ImportedValue imported = 23;
  int left = 20, right = 22;
  int direct_sum = $fixture.call(add, left, right);
  int aliased_sum = call(add, left, right);
  int direct_zero_sequence = $fixture.invoke() forty_two;
  int zero_sequence = invoke() forty_two;
  int one_sequence = invoke(42) identity;
  int direct_many_sequence = $fixture.invoke(20, 22) add;
  int many_sequence = invoke(20, 22) add;
  int direct_total = 0, total = 0;
  int call = 1;
  int range = 2;
  $fixture.swap(left, right);
  swap(left, right);
  $fixture.range(i, 1, 4) {
    direct_total += i;
  }
  range(i, 1, 4) {
    total += i;
  }
  printf(
    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    direct_value(), aliased_value(), record.direct_field,
    record.aliased_field, DIRECT_ENUMERATOR, ALIASED_ENUMERATOR,
    direct_sum, aliased_sum, direct_zero_sequence, zero_sequence,
    one_sequence, direct_many_sequence, many_sequence,
    left + right + call + range, direct_total, total, imported
  );
  return 0;
}
