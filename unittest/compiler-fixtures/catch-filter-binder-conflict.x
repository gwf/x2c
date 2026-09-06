#include "x2c.x"

void fail(void) {
  try {}
  catch %(invariant (first ?value) (second *value)): {
    value.repr();
  }
}
