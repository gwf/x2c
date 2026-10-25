#include "x2c.x"
#include <stdlib.h>

static int forty_two(void) {
  return 42;
}

typedef int MyInt;

static int statement_result;

meta static List private_int(String spelling, String value) {
  return %(declare (static int)
    (bindings
      (op = (bind $(x2c_ident(spelling)) ())
            (expr (int) (literal (int) $value)))));
}

meta static List rows_of(List target) => %($target);
meta static List same_rows(List rows) => rows;
meta static List return_rows(void) => %((return));

meta static List with_private_sibling(List target) =>
  %($target $(private_int("private_meta_sibling", "11")));

meta static List with_generated_sibling(List target) =>
  %($target $(private_int("private_generated_meta_sibling", "12")));

meta static List with_before_sibling(List target) =>
  %($(private_int("private_before_meta_sibling", "13")) $target);

macro Expression $call(Expr $callee, Expr @arguments) =>
  $callee(@arguments);

macro Expression $type_size(Type $value) => sizeof($value);
macro Expression $outer(Expr $value) => $type_size(int) + $value;
macro Expression $increment(Expr $value) => ($value) + 1;
macro Expression $nested_comma(Expr $value) => (0, $increment($value));
macro Expression $nested_size(Expr $value) => sizeof($increment($value));
macro Expression $list_value(Expr $value) => %($($value));
macro Expression $array_value(Expr $value) => %[$($increment($value)), 2];
macro Expression $lambda_value(Expr $value) => %!() => $increment($value);
macro Expression $parenthesized($value) => ($value);
macro Expression $absolute(Expr $value) using abs => abs($value);

macro Decorator $drop(Unit $target) {
}

macro Decorator $keep(Unit $target) {
  $target
}

macro Decorator $private_exact(Unit $target) {
  $target
  static int $x2c_ident("private_exact_helper") = 7;
}

macro Unit $nested_decorator_declarations() {
  static int nested_before = 1;
  $keep()
  static int nested_after = 2;

  static int $x2c_ident("nested_declaration_sum")(void) {
    return nested_before + nested_after;
  }
}

macro Decorator $preserve_meta(Unit $target) {
  @rows_of($target)
}

macro Unit $preserve_nested_meta_target(Unit $target) {
  @rows_of($target)
}

macro Unit $preserve_nested_meta_targets(Unit @targets) {
  @same_rows($targets)
}

macro Decorator $preserve_nested_meta(Unit $target) {
  $preserve_nested_meta_target($target);
}

macro Decorator $preserve_nested_meta_variadic(Unit $target) {
  $preserve_nested_meta_targets($target);
}

macro Decorator $private_name_sibling(Unit $target) {
  $target
  static int $x2c_ident("private_name_sibling") = 10;
}

macro Decorator $private_meta_sibling(Unit $target) {
  @with_private_sibling($target)
}

macro Decorator $private_generated_meta_sibling(Unit $target) {
  @with_generated_sibling($target)
}

macro Decorator $private_before_meta_sibling(Unit $target) {
  @with_before_sibling($target)
}

macro Unit $preserve_target(Unit $target) {
  $target
}

macro Decorator $preserve_nested(Unit $target) {
  $preserve_target($target);
}

macro Unit $discard_target(Unit $target) {
}

macro Decorator $discard_nested(Unit $target) {
  $discard_target($target);
}

macro Unit $preserve_targets(Unit @targets) {
  @targets
}

macro Unit $relay_targets(Unit @targets) {
  $preserve_targets(@targets);
}

macro Decorator $preserve_variadic(Unit $target) {
  $relay_targets($target);
}

macro Decorator $preserve_variadic_direct(Unit $target) {
  $preserve_targets($target);
}

$preserve_meta()
int preserved_public = 3;

$preserve_nested_meta()
int preserved_nested_meta_public = 7;

$preserve_nested_meta_variadic()
int preserved_nested_meta_variadic_public = 8;

$private_name_sibling()
int private_name_sibling_target = 9;

$private_meta_sibling()
int private_meta_sibling_target = 10;

$private_generated_meta_sibling()
int private_generated_meta_sibling_target = 11;

$private_before_meta_sibling()
int private_before_meta_sibling_target = 12;

$preserve_nested()
int preserved_nested_public = 4;

$discard_nested()
static int discarded_nested_static = 3;

$preserve_variadic()
int preserved_variadic_public = 5;

$preserve_variadic_direct()
int preserved_direct_variadic_public = 6;

$drop()
static int discarded_static = 1;

$drop() $keep()
static int stacked_private = 8;

$private_exact()
static int private_exact_target = 9;

$nested_decorator_declarations();

$drop()
static int discarded_private = 2;

macro Stmt $bare_return() {
  @return_rows()
}

macro Stmt $statement_item(Expr $value) {
  statement_result = $value;
}

macro Stmt $statement_outer(Name $statement_item) {
  $statement_item(13);
}

static void capture_statement(int value) {
  statement_result = value;
}

static void stop(void) {
  $bare_return();
}

int main(void) {
  int result = 0;
  int abs = 7;
  MyInt is = 3;
  List values = %(2);
  foreach (Var item, values) {
    result += item.integer();
    foreach (String item, %"a".words())
      result += item.len();
    result += item.integer();
  }
  stop();
  $statement_outer(capture_statement);
  return result == 5 && preserved_public == 3 &&
         preserved_nested_public == 4 &&
         preserved_variadic_public == 5 &&
         preserved_direct_variadic_public == 6 &&
         preserved_nested_meta_public == 7 &&
         preserved_nested_meta_variadic_public == 8 &&
         private_name_sibling_target == 9 &&
         private_name_sibling == 10 &&
         private_meta_sibling_target == 10 &&
         private_meta_sibling == 11 &&
         private_generated_meta_sibling_target == 11 &&
         private_generated_meta_sibling == 12 &&
         private_before_meta_sibling_target == 12 &&
         private_before_meta_sibling == 13 &&
         statement_result == 13 &&
         $call(forty_two) == 42 &&
         $outer(1) == sizeof(int) + 1 &&
         $nested_comma(41) == 42 &&
         $nested_size(41) == sizeof(int) &&
         $list_value(7).car().integer() == 7 &&
         $array_value(6)[0].integer() == 7 &&
         $lambda_value(6)().integer() == 7 &&
         $parenthesized(0) == 0 &&
         $absolute(-5) == 5 && abs == 7 && is == 3 &&
         private_exact_target == 9 && private_exact_helper == 7 &&
         nested_declaration_sum() == 3 ? 0 : 1;
}
