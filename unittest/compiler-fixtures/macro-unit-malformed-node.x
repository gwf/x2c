#include "x2c.x"

macro Unit $malformed() => {
  $(quote ((bogus 42)))...
}

$malformed();
