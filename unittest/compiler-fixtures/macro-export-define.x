// `export` is an ordinary identifier, so a C macro with that name applies.
#include "x2c.x"
#define export __attribute__((visibility("default")))

export int api(void) { return 4; }

int main(void) {
  printf("%d\n", api());
  return 0;
}
