#include "x2c.x"

macro Decorator $outer(Unit $target) => {
  $target
}

macro Decorator $discard(Unit $target) => {
}

$outer()
$discard()
static int value = 42;
