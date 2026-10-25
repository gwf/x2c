#include "x2c.x"

meta static List break_rows(void) => %((break));

macro Unit $bad() {
  @break_rows()
}

$bad();
