#include "x2c.x"

/* A composite initializer's elements are ordinary expressions and need the
   same resolution as any other operand. Without it a generated call or name
   reached emission unresolved and printed its marker into the C. */

typedef struct Pair { int a, b; } Pair;

static int twice(int n) { return n + n; }

macro Unit $probe.pair(Name $fn) => {
  static Pair $fn(void) {
    Pair value = $(x2c.expr.composite (list
      (x2c.expr.call
        (x2c.expr.ident (x2c.ident "twice"))
        (x2c.literal.int 3))
      (x2c.literal.int 2)));
    return value;
  }
}

$probe.pair(built);

int main(void) {
  Pair pair = built();
  printf("%d %d\n", pair.a, pair.b);
  return 0;
}
