#include "x2c.x"

macro Unit $discard_target(Unit $target) => {
}

macro Unit $relay_targets(Unit $targets...) => {
  $discard_target($targets...);
}

macro Decorator $drop(Unit $target) => {
  $relay_targets($target);
}

$drop()
int visible_value = 42;
