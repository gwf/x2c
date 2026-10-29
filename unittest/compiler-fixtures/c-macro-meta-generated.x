#include "x2c.x"
#include "c-macro-meta-generated/header.h"

#define FUNC meta int value(void) => 42;
FUNC
HEADER_META
int main(void) {
  printf("%d %d\n", $value(), $header_value());
  return 0;
}
