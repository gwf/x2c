#include "x2c.x"

macro Entry $invalid_rows() => {
  $(list 42)...
}

Map values = %{ ${$invalid_rows()} };
