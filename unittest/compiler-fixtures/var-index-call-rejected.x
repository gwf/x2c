#include "x2c.x"

int main(void) {
  Array functions = [%!(int n) => n + 1];
  functions[0](3);
  return 0;
}
