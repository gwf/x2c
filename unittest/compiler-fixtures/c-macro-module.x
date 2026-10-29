#include "x2c.x"

#define BODY int before(void) => 1; module {"c-macro-module/part.x"} int after(void) => 2;
BODY
int main(void) {
  printf("%d\n", before() + member() + after());
  return 0;
}
