#include "x2c.x"

/* A defer captures a macro's private local by address; the capture
   names the private local even though the lowering that writes it runs
   outside the scope that declared it. */

static void show(int value) { printf("%d\n", value); }

macro Stmt $demo() {
  int out = 7;
  defer show(out);
  out = 8;
}

int main(void) {
  $demo();
  return 0;
}
