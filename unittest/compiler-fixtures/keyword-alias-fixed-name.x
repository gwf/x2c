#include "x2c.x"

macro Decorator $fixture.identity(Statement $target) => {
  $target
}

keyword if $fixture.identity;
