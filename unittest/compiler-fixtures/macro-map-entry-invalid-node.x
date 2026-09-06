#include "x2c.x"

macro Entry $invalid_row() => {
  $(list (list 'map-entry (x2c.literal.string "key")))...
}

Map values = %{ ${$invalid_row()} };
