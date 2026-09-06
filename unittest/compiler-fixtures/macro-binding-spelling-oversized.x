#include "x2c.x"

macro Expression $spelling() => (
  $(x2c.binding.spelling '(binding 4294967297 "value"))
)

int value = $spelling();
