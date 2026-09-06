#include "x2c.x"
#include <stdlib.h>

static int forty_two(void) {
  return 42;
}

typedef int MyInt;

static int statement_result;

$(defun fixture.private-sibling ()
  `(declare (static int)
    (bindings
      (op = (bind ,(x2c.ident "private_generated_lisp_sibling") ())
            (expr (int) (literal (int) "12"))))))

$(defun fixture.private-before-sibling ()
  `(declare (static int)
    (bindings
      (op = (bind ,(x2c.ident "private_before_lisp_sibling") ())
            (expr (int) (literal (int) "13"))))))

macro Expression $call(Expr $callee, Expr $arguments...) => (
  $callee($arguments...)
)

macro Expression $type_size(Type $value) => (sizeof($value))
macro Expression $outer(Expr $value) => ($type_size(int) + $value)
macro Expression $increment(Expr $value) => (($value) + 1)
macro Expression $nested_comma(Expr $value) => ((0, $increment($value)))
macro Expression $nested_size(Expr $value) => (sizeof($increment($value)))
macro Expression $list_value(Expr $value) => (%(${$value}))
macro Expression $array_value(Expr $value) => (%[${$increment($value)}, 2])
macro Expression $lambda_value(Expr $value) => (%!() => $increment($value))
macro Expression $parenthesized($value) => (($value))
macro Expression $absolute(Expr $value) => (abs($value))

macro Decorator $drop(Unit $target) => {
}

macro Decorator $keep(Unit $target) => {
  $target
}

macro Decorator $private_exact(Unit $target) => {
  $target
  static int $(x2c.ident "private_exact_helper") = 7;
}

macro Unit $nested_decorator_declarations() => {
  static int nested_before = 1;
  $keep()
  static int nested_after = 2;

  static int $(x2c.ident "nested_declaration_sum")(void) {
    return nested_before + nested_after;
  }
}

macro Decorator $preserve_lisp(Unit $target) => {
  $(list $target)...
}

macro Unit $preserve_nested_lisp_target(Unit $target) => {
  $(list $target)...
}

macro Unit $preserve_nested_lisp_targets(Unit $targets...) => {
  $(append $targets (list))...
}

macro Decorator $preserve_nested_lisp(Unit $target) => {
  $preserve_nested_lisp_target($target);
}

macro Decorator $preserve_nested_lisp_variadic(Unit $target) => {
  $preserve_nested_lisp_targets($target);
}

macro Decorator $private_name_sibling(Unit $target) => {
  $target
  static int $(x2c.ident "private_name_sibling") = 10;
}

macro Decorator $private_lisp_sibling(Unit $target) => {
  $(list $target
    `(declare (static int)
      (bindings
        (op = (bind ,(x2c.ident "private_lisp_sibling") ())
              (expr (int) (literal (int) "11"))))))...
}

macro Decorator $private_generated_lisp_sibling(Unit $target) => {
  $(list $target (fixture.private-sibling))...
}

macro Decorator $private_before_lisp_sibling(Unit $target) => {
  $(list (fixture.private-before-sibling) $target)...
}

macro Unit $preserve_target(Unit $target) => {
  $target
}

macro Decorator $preserve_nested(Unit $target) => {
  $preserve_target($target);
}

macro Unit $discard_target(Unit $target) => {
}

macro Decorator $discard_nested(Unit $target) => {
  $discard_target($target);
}

macro Unit $preserve_targets(Unit $targets...) => {
  $targets...
}

macro Unit $relay_targets(Unit $targets...) => {
  $preserve_targets($targets...);
}

macro Decorator $preserve_variadic(Unit $target) => {
  $relay_targets($target);
}

macro Decorator $preserve_variadic_direct(Unit $target) => {
  $preserve_targets($target);
}

$preserve_lisp()
int preserved_public = 3;

$preserve_nested_lisp()
int preserved_nested_lisp_public = 7;

$preserve_nested_lisp_variadic()
int preserved_nested_lisp_variadic_public = 8;

$private_name_sibling()
int private_name_sibling_target = 9;

$private_lisp_sibling()
int private_lisp_sibling_target = 10;

$private_generated_lisp_sibling()
int private_generated_lisp_sibling_target = 11;

$private_before_lisp_sibling()
int private_before_lisp_sibling_target = 12;

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

#pragma private
$drop()
int discarded_private = 2;
#pragma public

macro Statement $bare_return() => {
  $(quote ((return)))...
}

macro Statement $statement_item(Expr $value) => {
  statement_result = $value;
}

macro Statement $statement_outer(Name $statement_item) => {
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
         preserved_nested_lisp_public == 7 &&
         preserved_nested_lisp_variadic_public == 8 &&
         private_name_sibling_target == 9 &&
         private_name_sibling == 10 &&
         private_lisp_sibling_target == 10 &&
         private_lisp_sibling == 11 &&
         private_generated_lisp_sibling_target == 11 &&
         private_generated_lisp_sibling == 12 &&
         private_before_lisp_sibling_target == 12 &&
         private_before_lisp_sibling == 13 &&
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
