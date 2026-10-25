#include "x2c.x"

static void nothing(void) { }

/* A void expression has no value to convert to an element. */
int main(void) {
  List xs = $(1, nothing());
  return xs.len();
}
