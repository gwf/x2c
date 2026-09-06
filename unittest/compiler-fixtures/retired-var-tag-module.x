#include "x2c.x"

typedef struct Module { int value; } Module;

int main(void) {
  Module value = { 1 };
  Var boxed = value;
  (void) boxed;
  return 0;
}
