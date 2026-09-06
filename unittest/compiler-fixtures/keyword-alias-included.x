#include "x2c.x"
#include "keyword-alias-included/source.x"

static int identity(void) {
  return 0;
}

int main(void) {
  return included_values().len() + identity();
}
