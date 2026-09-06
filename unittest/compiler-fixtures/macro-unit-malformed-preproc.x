#include "x2c.x"

macro Unit $malformed() => {
  $(quote ((preproc 42)))...
}

$malformed();
