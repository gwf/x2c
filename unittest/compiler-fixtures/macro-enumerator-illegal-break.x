#include "x2c.x"

meta static List break_rows(void) => %((break));

macro Enumerator $bad() {
  @break_rows()
}

typedef enum Broken {
  $bad()
} Broken;
