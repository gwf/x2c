// `export` marks the compile-time import that follows it. Before any other
// form it is an ordinary identifier, so a C macro named `export` applies.
#include "x2c.x"
#define export __attribute__((visibility("default")))

export int api(void) { return 4; }

int main(void) {
  printf("%d\n", api());
  return 0;
}
