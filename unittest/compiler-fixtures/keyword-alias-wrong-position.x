#include "x2c.x"

macro Decorator $fixture.function_identity(Function $target) {
  @(Code.body $target)
}

keyword function_only $fixture.function_identity;

function_only
static int value = 42;
