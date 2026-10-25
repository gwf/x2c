#include "x2c.x"

meta static List no_rows(void) => %();

macro Enumerator $bad() {
  $no_rows()
}

typedef enum Broken {
  A,
  $bad()
} Broken;
