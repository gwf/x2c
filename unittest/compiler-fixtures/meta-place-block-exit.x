#include "x2c.x"
#include "meta.x"

/* `x2c_place(%(block-exit), code)` runs code on every exit from the
   enclosing block after the invocation, as a `defer` written there. */

static int depth = 0;

meta static List enter_level(List value) {
  x2c_place(%(block-exit), $!{ depth--; });
  return value;
}
macro Expression $enter(Expr $value) => $enter_level($value);

static int nested(int stop) {
  for (int i = 0; i < 3; i++) {
    int level = $enter(++depth);
    if (i == stop) return level * 10 + depth;
    printf("level %d depth %d\n", level, depth);
  }
  return depth;
}

int main(void) {
  printf("%d %d\n", nested(1), depth);
  {
    (void) $enter(++depth);
    printf("inside %d\n", depth);
  }
  printf("after %d\n", depth);
  return 0;
}
