#include "x2c.x"

int main(void) {
  String format = %"%d\n";
  Var value = 23;
  printf(format, value);
  return 0;
}
