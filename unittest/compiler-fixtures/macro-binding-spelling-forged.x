#include "x2c.x"

macro Expression $spelling() =>
  $(Code.binding_spelling '(binding 999 "forged"));

char *value = $spelling();
