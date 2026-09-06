#include "x2c.x"

void fail(void) {
  try {}
  catch %(invariant (value (!not ?value))): {
    value.repr();
  }
}
