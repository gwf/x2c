#pragma once

macro Decorator $x2c.foreign.alias(
  Unit $declaration,
  Expr $native
) {
  @(list (list 'falias $declaration $native))
}

macro Expression $x2c.callback.adapt(
  Expr $target,
  Expr $source
) =>
  $(list 'expr nil (list 'tadapt $target $source));

macro Decorator $x2c.foreach(
  Stmt $body,
  Decl $declaration,
  Expr $collection
) {
  using $iterator, $item, $pair, $object, $cursor;
  @(foreach.expand
    $declaration $collection $body
    $iterator $item $pair $object $cursor)
}

keyword foreach $x2c.foreach;

macro Decorator $x2c.auto.region(Stmt $body) {
  @(scope.expand $body ())
}

macro Decorator $x2c.auto.destination(Stmt $body, Expr $destination) {
  @(scope.expand $body (list $destination))
}

macro Decorator $scope(Stmt $body, Expr @destination) {
  @(scope.expand $body $destination)
}

/* Built-in macros install before any declaration of a unit, including the
   unit that reads `lib/meta.x`, so `$Code.type` has no prototype here. The
   Lisp form reaches the compiler's binding when the macro expands. */
macro Decorator $let(Stmt $body, Expr $place, Expr $value) {
  {
    $(Code.type $place) *address = &$place;
    $(Code.type $place) previous = *address;
    defer *address = previous;
    *address = $value;
    $body
  }
}

macro Decorator $x2c.with(Stmt $body, Expr @assignments) {
  using $address, $previous;
  $(with.expand $body $assignments $address $previous)
}

macro Decorator $lock(Stmt $body, Expr $mutex) {
  {
    $(list "Mutex") held = $mutex;
    held.lock();
    defer held.unlock();
    $body
  }
}

macro Expression $auto(Expr $value) => $(auto.expand $value);

macro Decorator $class(NamedType $definition) {
  @(class.expand $definition)
}

keyword class $class;
