#include "x2c.x"

/* Destructured names a lambda shares by reference live in cells, so the
   lambda sees later writes and outlives the frame that declared them. */
static Func make(void) {
  int (a, b) = %(1 2);
  (int c, Var d) = %(3 4);
  Func f = %!() using &a, &c => {
    a++;
    c += 10;
    return a + b + c;
  };
  a = 5;
  (void) d;
  return f;
}

int main(void) {
  Func f = make();
  int x = f(), y = f();
  printf("%d %d\n", x, y);
  return x == 21 && y == 32 ? 0 : 1;
}
