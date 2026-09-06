#include "x2c.x"

macro Statement $scoped(Decl $declaration) => {
  $declaration
}

int main(void) {
  $scoped(int left, right);
  return 0;
}
