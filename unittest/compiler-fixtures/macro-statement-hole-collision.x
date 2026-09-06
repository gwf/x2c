#include "x2c.x"

macro Statement $item() => {
  ;
}

macro Statement $broken(Expr $item) => {
  $item;
}

int main(void) {
  $broken(0);
  return 0;
}
