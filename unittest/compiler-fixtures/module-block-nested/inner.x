#include "offset.h"
static int middle = 5;

module {
  "inner/deep.x",
}

static int inner_total(void) => base + middle + deep_value() + OFFSET;
