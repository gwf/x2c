#include "x2c.x"

#define BODY(path) module {path}
BODY("c-macro-module/part.x")
int main(void) {
  printf("%d\n", member());
  return 0;
}
