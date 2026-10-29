// A `_` target in `T (a, b) = source;` discards its element and declares
// nothing, in one pattern more than once, across statements in one scope,
// and inside a template; a foreach `_` stays an ordinary name.
#include "x2c.x"

static int calls = 0;

static List values(void) {
  calls++;
  return %(1 2 3);
}

macro Stmt $middle(Expr $source, Name $n) {
  Var (_, mid, _) = $source;
  $n = mid;
}

int main(void) {
  Var (_, _, third) = values();
  int (_, second) = values();
  Var (_, _) = values();
  Var middle;
  $middle(values(), middle);
  int total = 0;
  foreach (Var (_, value) in %((1 10) (2 20))) total += value.integer();
  printf("%ld %d %ld %d %d\n",
         third.integer(), second, middle.integer(), total, calls);
  return 0;
}
