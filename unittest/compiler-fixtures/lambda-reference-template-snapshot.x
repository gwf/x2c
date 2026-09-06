#include "x2c.x"
macro Expression $snapshot(Expr $value) => (%!() => $value)
static Func snapshot(int &value) => $snapshot(value);
int main(void) {
  int value = 1;
  Func read = snapshot(value);
  value = 2;
  printf("snapshot=%ld outer=%d\n", read().integer(), value);
  return 0;
}
