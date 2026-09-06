#include "x2c.x"

int main(void) {
  Var (first, second) = %(1 2);
  try {
    second = 3;
  }
  catch: {}
  return first.int() == 1 && second.int() == 3 ? 0 : 1;
}
