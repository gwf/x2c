/* A macro definition in a template may take a component of its name from a
   Name hole, as `$W.$m` or `$$m`, so one generator template stamps out a
   family of method-form macros. A call in the generated template that
   names the generated macro is its method. */

#include "x2c.x"

typedef struct W { int n; } *W;

static int W.add(W w, int k) => w.n + k;
static int W.sub(W w, int k) => w.n - k;
static void W.open(W w) { printf("open %d\n", w.n); }
static void W.close(W w) { printf("close %d\n", w.n); }

macro Unit $gen(Name $m) {
  macro Expression $W.$m(Expr $w, Expr $k) => $w.$m($k * 10);
}
$gen(add);
$gen(sub);

macro Unit $block(Name $begin, Name $end) {
  macro Decorator $W.$begin(Stmt $body, Expr $w) {
    {
      W block = $w;
      block.$begin();
      defer block.$end();
      $body
    }
  }
}
$block(open, close);

macro Unit $wrap(Name $m) {
  macro Expression $$m(Expr $x) => $x + 1;
}
$wrap(inc);

int main(void) {
  struct W s = { 1 };
  W w = &s;
  printf("%d %d %d %d\n", w.add(2), w.sub(2), $W.add(w, 3), $inc(4));
  w.open() printf("inside\n");
  return 0;
}
