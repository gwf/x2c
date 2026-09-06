#include "x2c.x"

void fail(void) {
  raise %(invariant (<owner> "probe"));
}
