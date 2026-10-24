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

/* `with (place = value, ...) { ... }` at statement position expands
   this decorator; `with.expand` nests one saving block per assignment. */
macro Decorator $x2c.with(Stmt $body, Expr @assignments) {
  $(with.expand $body $assignments)
}

macro Decorator $lock(Stmt $body, Expr $mutex) {
  {
    Mutex held = $mutex;
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
