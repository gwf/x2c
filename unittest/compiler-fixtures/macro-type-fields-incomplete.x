#include "x2c.x"

struct IncompleteRecord;

macro Unit $inspect(Type $type) => {
  $(x2c.type.fields $type)...
}

$inspect(struct IncompleteRecord);
