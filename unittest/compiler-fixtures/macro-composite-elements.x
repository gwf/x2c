#include "x2c.x"

/* A composite initializer's elements are ordinary expressions and need the
   same resolution as any other operand. Without it a generated call or name
   reached emission unresolved and printed its marker into the C. */

typedef struct Pair { int a, b; } Pair;

static int twice(int n) { return n + n; }

meta static List pair_syntax(void) {
  return %(expr () (composite (commas
    (expr () (call (expr () (ident $(x2c_ident("twice"))))
      (args (expr (int) (literal (int) "3")))))
    (expr (int) (literal (int) "2")))));
}

macro Unit $probe.pair(Name $fn) {
  static Pair $fn(void) {
    Pair value = $pair_syntax();
    return value;
  }
}

$probe.pair(built);

int main(void) {
  Pair pair = built();
  printf("%d %d\n", pair.a, pair.b);
  return 0;
}
