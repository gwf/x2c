#include "x2c.x"

macro Unit $ambiguous_pointer($T) => {
  static void ambiguous_pointer_body(void) {
    $T *local;
  }
}

$ambiguous_pointer(long);
