#include "x2c.x"

macro Decorator $identity(Function $function) {
  @(Code.body $function)
}

$identity()
static int value = 42;
