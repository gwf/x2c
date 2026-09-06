#include "x2c.x"

macro Decorator $identity(Unit $target) => {
  $target
}

$identity();
static int value = 42;
