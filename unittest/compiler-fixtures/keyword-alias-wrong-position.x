#include "x2c.x"

macro Decorator $fixture.function_identity(Function $target) => {
  $(x2c.function.body $target)...
}

keyword function_only $fixture.function_identity;

function_only
static int value = 42;
