#include "x2c.x"

int main(void) {
  Var value = NULL;
  printf("null=%d\n", value.is_null());
  return value.is_null() ? 0 : 1;
}
