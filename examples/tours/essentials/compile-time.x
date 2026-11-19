/* The same language computes values and constructs source at compile time.
   meta enables compilation-time calls; $ requests one. Macros capture
   syntax. Declared macro locals are private; free names normally come from
   the caller. */
meta static int cube(int n) => n * n * n;
macro Decorator $twice(Stmt $body) {
  { for (int repeat = 0; repeat < 2; repeat++) $body }
}
keyword twice $twice;

int main(void) {
  auto {
    int n = 3, total = 0;
    twice { total += cube(n); }
    printf("compile time: cube %d; runtime total %d\n", $cube(3), total);
    // Lists can also be executable data. Lisp evaluates them at runtime.
    List expression = %(+ 2 3);
    Lisp lisp = auto Lisp.new();
    printf("   Lisp %s; native %d\n", lisp.eval(expression), 2 + 3);
  }
  return 0;
}
