#include "x2c.x"

typedef struct Clock { int value; } Clock;

int main(void) {
  Clock value = { 1 };
  Var boxed = value;
  (void) boxed;
  return 0;
}
