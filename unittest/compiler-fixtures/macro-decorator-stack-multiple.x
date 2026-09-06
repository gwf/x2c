#include "x2c.x"

macro Decorator $outer(Unit $target) => {
  $target
}

macro Decorator $multiple(Unit $target) => {
  $target
  static int sibling = 7;
}

$outer()
$multiple()
static int value = 42;
