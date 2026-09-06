#include "x2c.x"

int value = $later(1);

macro Expression $later($value) => ($value)
