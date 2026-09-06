#include "x2c.x"

macro Decorator $identity(Function $function) => {
  $(x2c.function.body $function)...
}

$identity()
static int value = 42;
