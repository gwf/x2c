#include "x2c.x"

macro Unit $discard_target(Unit $target) => {
}

macro Decorator $drop(Unit $target) => {
  $discard_target($target);
}

$drop()
int visible_value = 42;
