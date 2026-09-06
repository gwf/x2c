#include "x2c.x"

macro Expression $spelling() => (
  $(x2c.binding.spelling "not valid")
)

char *value = $spelling();
