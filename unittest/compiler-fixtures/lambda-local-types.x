#include "x2c.x"
#include "rewrite.x"
#include "first.x"
#include "second.x"

meta static Code check_original_definition(Code function, String rule) {
  if (Code.name(function) != "record_reference") return function;
  if (!Code.body(function).search(%(struct ? (fields *))))
    x2c_diagnostic_fail("function rule lost the local definition", NULL);
  x2c_place(%(unit-init), $!{ printf("%s sees local definition\n", $rule); });
  return function;
}

$rewrite(%(function (static int) *))
meta Code typed_function(Code function) =>
  check_original_definition(function, "typed");

$rewrite(%(function ? *))
meta Code generic_function(Code function) =>
  check_original_definition(function, "generic");

static int record_reference(void) {
  struct Record { int count; } value = {41};
  Func f = %!() using &value => ++value.count;
  return f().int();
}

static int typedef_reference(void) {
  typedef struct { int count; } Record;
  Record value = {41};
  Func f = %!() using &value => ++value.count;
  return f().int();
}

static int enum_snapshot(void) {
  enum Mode { ready = 41 } value = ready;
  Func f = %!() => value + 1;
  return f().int();
}

static int distinct_local_types(void) {
  struct Record { int other; } value = {10};
  enum Mode { ready = 20 } mode = ready;
  Func outer = %!() using &value => value.other + mode;
  {
    struct Record { int count; } value = {11};
    enum Mode { ready = 21 } mode = ready;
    Func inner = %!() using &value => value.count + mode;
    return outer().int() + inner().int();
  }
}

static int dependent_types(void) {
  struct Inner { int count; };
  struct Outer { struct Inner inner; } value = {{41}};
  Func f = %!() using &value => ++value.inner.count;
  return f().int();
}

static int declaration_order(void) {
  struct B;
  struct A { struct B *next; };
  struct B { struct A value; };
  struct A value = {0};
  Func f = %!() using &value => value.next == NULL;
  return f().int();
}

static int enum_bound(void) {
  enum { width = 1 };
  struct Record { int values[width]; } value = {{41}};
  Func f = %!() using &value => ++value.values[0];
  return f().int();
}

static int nested_type(void) {
  struct Outer { struct Inner { int count; } inner; } value = {{41}};
  Func f = %!() using &value => ++value.inner.count;
  return f().int();
}

static Func escaped_record(void) {
  struct Record { int count; } value = {41};
  return %!() using &value => ++value.count;
}

static int anonymous_member(void) {
  struct Outer { struct { int count; }; } value = {{41}};
  Func f = %!() using &value => ++value.count;
  return f().int();
}

int main(void) {
  Func escaped = escaped_record();
  int first = escaped().int(), second = escaped().int();
  printf("%d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    record_reference(), typedef_reference(),
    enum_snapshot(), distinct_local_types(), dependent_types(),
    declaration_order(), enum_bound(), nested_type(),
    first_inline_record(), second_inline_record(),
    first, second, anonymous_member());
  return 0;
}
