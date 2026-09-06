#include "x2c.x"

void fail(List values) {
  raise %(invariant (detail @values));
}
