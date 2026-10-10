#include "x2c.x"

struct IncompleteRecord;

macro Unit $inspect(Type $type) {
  @(Type.fields $type)
}

$inspect(struct IncompleteRecord);
