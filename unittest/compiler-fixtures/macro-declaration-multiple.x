#include "x2c.x"

macro Stmt $scoped(Decl $declaration) {
  $declaration
}

int main(void) {
  $scoped(int left, right);
  return 0;
}
