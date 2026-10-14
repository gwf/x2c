#include "offset.h"
module int middle = 5;

module {
  "inner/deep.x",
}

module int inner_total(void) => base + middle + deep_value() + OFFSET;
