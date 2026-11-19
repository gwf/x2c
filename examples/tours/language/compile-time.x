#include "meta.x"

/* An ordinary call runs now; $ calls a meta function during translation. A
   macro receives syntax. Its declared locals are private per expansion;
   free names resolve at the call site unless kept with using. */
meta static int cube(int n) => n * n * n;
static int factor = 2;
macro Expression $scaled(Expr $n) => $n * factor;
macro Expression $fixed(Expr $n) using factor => $n * factor;

macro Decorator $twice(Stmt $body) {
  { for (int repeat = 0; repeat < 2; repeat++) $body }
}
keyword twice $twice;

// A quotation writes generated code in source form; the hole inserts syntax.
meta static List report_code(List value) =>
  $!{ printf("   generated report: %s\n", (Var) $value); };
macro Stmt $report(Expr $value) => $report_code($value);

int main(void) {
  auto {
    int n = 3;
    printf("meta: runtime %d; compile time %d\n", cube(n), $cube(3));
    int factor = 10;
    printf("   caller name %d; kept name %d\n", $scaled(3), $fixed(3));
    int total = 0;
    twice { total++; }
    $report(total);
    // Lisp is a runtime library, not the implementation of meta functions.
    Lisp lisp = auto Lisp.new();
    printf("   runtime Lisp: %s\n", lisp.eval(%(+ 2 3)));
  }
  return 0;
}
