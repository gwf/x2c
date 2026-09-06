#include "x2c.x"

macro Unit $inspect(Type $type) => {
  $(x2c.type.fields $type)...
}

$inspect(int);
