#include "x2c.x"
int main(int argc, char **argv) {
  (void) argv;
  Var value = argc ? puts("a") : puts("b");
  (void) value;
  return 0;
}
