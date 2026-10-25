#include "x2c.x"

meta static List bogus_rows(void) => %((bogus 42));

macro Unit $malformed() {
  @bogus_rows()
}

$malformed();
