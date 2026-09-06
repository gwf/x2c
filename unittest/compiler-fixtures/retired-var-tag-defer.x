#include "x2c.x"

typedef struct Defer { int value; } Defer;

int main(void) {
  Defer value = { 1 };
  Var boxed = value;
  (void) boxed;
  return 0;
}
