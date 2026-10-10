#include "x2c.x"

macro Expression $spelling() =>
  $(Code.binding_spelling '(binding 4294967297 "value"));

int value = $spelling();
