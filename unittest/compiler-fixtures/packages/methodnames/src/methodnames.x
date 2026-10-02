// A generated method keeps the source owner of its ordinary prototype.
#pragma once
#include "x2c.x"

typedef struct Value { int number; } Value;

int Value.read(Self value);

macro Unit $reader(Type $type) {
  int $type.read(Self value) => value.number;
}

$reader(Value);

int Value.direct(Self value) => value.number;
