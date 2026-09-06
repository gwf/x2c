#include "x2c.x"

macro Unit $discard_target(Unit $target) => {
}

macro Unit $relay_target(Unit $target) => {
  $discard_target($target);
}

macro Decorator $drop(Unit $target) => {
  $relay_target($target);
}

$drop()
int visible_value = 42;
