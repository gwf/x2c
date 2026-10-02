#include "x2c.x"

typedef int &Ref;

int main(void) {
  (Ref first, Ref second) = %(1 2);
  return 0;
}
