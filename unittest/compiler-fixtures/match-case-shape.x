#include "x2c.x"

int main(void) {
  Var v = 42;
  match (v) {
    case 42: return 1;
  }
  return 0;
}
