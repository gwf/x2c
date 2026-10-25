#include "x2c.x"

meta static List preproc_rows(void) => %((preproc 42));

macro Unit $malformed() {
  @preproc_rows()
}

$malformed();
