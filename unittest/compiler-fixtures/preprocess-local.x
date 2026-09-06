#include "x2c.x"
#include "preprocess-values.h"

int main(void) {
  printf("%d\n", FIXTURE_VALUE);
  return FIXTURE_VALUE == 37 ? 0 : 1;
}
