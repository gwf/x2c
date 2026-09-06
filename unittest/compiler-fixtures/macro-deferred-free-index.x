#include "x2c.x"

macro Expression $read_free_name() => (
  missing_values[0]
)

int value = $read_free_name();
