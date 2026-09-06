#include "x2c.x"

void fail(void) {
  try {}
  catch %(alloc-fail) {}
}
