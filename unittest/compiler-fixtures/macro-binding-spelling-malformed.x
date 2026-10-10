#include "x2c.x"

macro Expression $spelling() =>
  $(Code.binding_spelling '(binding "malformed"));

char *value = $spelling();
