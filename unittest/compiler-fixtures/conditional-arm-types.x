#include "x2c.x"

// Arms of one declared type keep it; mixed arms still widen or box.
typedef unsigned long Ticks;

static Var pick(int flag) {
  return flag ? <*y> : <*>;
}

static Ticks ticks(int flag) {
  Ticks fast = 1, slow = 2;
  return flag ? fast : slow;
}

int main(void) {
  int flag = 1;
  Var symbol = flag ? <*x> : <?x>;
  Var boxed = flag ? 7 : symbol;
  long widened = flag ? 3 : 4L;
  printf("%s %s %s %ld %lu\n", Var.repr(symbol), Var.repr(pick(1)),
         Var.repr(boxed), widened, (unsigned long) ticks(0));
  return 0;
}
