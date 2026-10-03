#include "x2c.x"

macro Stmt $item() {
  ;
}

macro Stmt $broken(Expr $item) {
  $item;
}

int main(void) {
  $broken(0);
  return 0;
}
