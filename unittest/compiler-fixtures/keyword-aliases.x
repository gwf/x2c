#include "x2c.x"

$(import "keyword-aliases-import.xmacro")

macro Decorator $fixture.increment(Expr $target) => ($target + 1)

macro Decorator $fixture.twice_value(Expr $target) => ($target * 2)

macro Decorator $fixture.frozen(Expr $target) => ($target + 4)

macro Decorator $fixture.repeat(Statement $target) => {
  $target
  $target
}

macro Decorator $fixture.once(Statement $target) => {
  {
    $target
  }
}

macro Decorator $fixture.preserve_field(Field $target) => {
  $target
}

macro Decorator $fixture.preserve_unit(Unit $target) => {
  $target
}

static int calculate(int value) {
  return value + 10;
}

static int before_alias(void) {
  return calculate(1);
}

keyword calculate $fixture.increment;

static int first_alias(void) {
  return calculate 2;
}

keyword calculate $fixture.twice_value;
keyword frozen $fixture.frozen;
keyword imported $fixture.imported;
keyword repeat $fixture.repeat;
keyword once $fixture.once;
keyword preserve_field $fixture.preserve_field;
keyword preserve_unit $fixture.preserve_unit;

static int frozen_before_redefinition(void) {
  return frozen 1;
}

macro Decorator $fixture.frozen(Expr $target) => ($target * 10)

static int frozen_after_redefinition(void) {
  return frozen 1;
}

$fixture.preserve_unit()
static int direct_unit = 3;

preserve_unit
static int aliased_unit = 4;

preserve_unit
$fixture.preserve_unit()
static int stacked_unit = 5;

typedef struct KeywordRecord {
  $fixture.preserve_field()
  int direct_field;

  preserve_field
  int aliased_field;
} KeywordRecord;

$fixture.imported()
static int direct_function(void) {
  return 7;
}

imported
static int aliased_function(void) {
  return 8;
}

imported
$fixture.imported()
static int stacked_function(void) {
  return 9;
}

static int second_alias(void) {
  return calculate 3;
}

int main(void) {
  KeywordRecord record = { 1, 2 };
  int imported = 6;
  int statements = 0;
  int conditional = 0;
  $fixture.repeat()
  statements++;
  repeat {
    statements += 2;
  }
  if (1) once conditional++;
  printf(
    "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    before_alias(), first_alias(), second_alias(),
    frozen_before_redefinition(), frozen_after_redefinition(),
    $fixture.increment() 2, $fixture.twice_value() 3, statements,
    conditional,
    direct_unit, aliased_unit, stacked_unit,
    record.direct_field, record.aliased_field,
    direct_function(), aliased_function(), stacked_function(), imported
  );
  return 0;
}

static void direct_captured_raise(void) {
  $fixture.once()
  {
    if (0)
      raise %(invariant);
  }
}

static void aliased_captured_raise(void) {
  once {
    if (0)
      raise %(invariant);
  }
}
