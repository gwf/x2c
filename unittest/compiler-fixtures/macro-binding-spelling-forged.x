#include "x2c.x"

macro Expression $spelling() => (
  $(x2c.binding.spelling '(binding 999 "forged"))
)

char *value = $spelling();
