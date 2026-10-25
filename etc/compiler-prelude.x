/*  compiler-prelude.x -- the syntax every unit starts with

    Copyright (c) 2026 Gary William Flake

    The compiler collects this source before the runtime prelude, so its
    macros and keyword aliases are visible to every unit, including the
    runtime's own. The macros expand through the native algorithms in
    `src/builtins.x`, which these prototypes name.
*/

#pragma once

#include "common-types.x"

meta List _x2c_scope_expand(List, List);
meta List _x2c_with_expand(List, List);
meta List _x2c_foreach_expand(List, List, List, Var, Var, Var, Var, Var);
meta List _x2c_auto_expand(List);
meta List _x2c_class_expand(List);
meta List _x2c_foreign_alias(List, List);
meta List _x2c_callback_adapt(List, List);

macro Decorator $scope(Stmt $body, Expr @destination) {
  @_x2c_scope_expand($body, $destination)
}

macro Decorator $x2c.foreign.alias(Unit $declaration, Expr $native) {
  @_x2c_foreign_alias($declaration, $native)
}

macro Expression $x2c.callback.adapt(Expr $target, Expr $source) =>
  $_x2c_callback_adapt($target, $source);

macro Decorator $x2c.foreach(
  Stmt $body,
  Decl $declaration,
  Expr $collection
) {
  using $iterator, $item, $pair, $object, $cursor;
  @_x2c_foreach_expand(
    $declaration, $collection, $body,
    $iterator, $item, $pair, $object, $cursor)
}

keyword foreach $x2c.foreach;

macro Decorator $x2c.auto.region(Stmt $body) {
  $scope() $body
}

macro Decorator $x2c.auto.destination(Stmt $body, Expr $destination) {
  $scope($destination) $body
}

/* `with (place = value, ...) { ... }` at statement position expands
   this decorator, which nests one saving block per assignment. */
macro Decorator $x2c.with(Stmt $body, Expr @assignments) {
  @_x2c_with_expand($body, $assignments)
}

macro Decorator $lock(Stmt $body, Expr $mutex) {
  {
    Mutex held = $mutex;
    held.lock();
    defer held.unlock();
    $body
  }
}

macro Expression $auto(Expr $value) => $_x2c_auto_expand($value);

macro Decorator $class(NamedType $definition) {
  @_x2c_class_expand($definition)
}

keyword class $class;
