#include "x2c.x"

macro Expression $spelling() => (
  $(x2c.binding.spelling '(binding "malformed"))
)

char *value = $spelling();
