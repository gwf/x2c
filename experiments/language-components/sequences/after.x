/* Registers a postlude; the compiler retains the declaration sequence. */
#pragma once
#include "meta.x"

meta Code register_after_initialization(Code function, Code pattern) =>
  function.register_after_initialization(pattern.value(), NULL);

macro Decorator $after_initialization(Unit $function, Expr $pattern) {
  @register_after_initialization($function, $pattern)
}
