/* A `Decl` hole forwards its captured declaration into a `foreach` header
   in a template; the declared variable is typed and visible in the body.
   The caller may separate the declaration from the next argument with
   `in`, as `foreach` does, including in a method form. */

#include "x2c.x"

typedef struct Ui { int *depth; } Ui;

macro Decorator $Ui.each(Stmt $body, Expr $ui, Decl $element, Expr $items) {
  {
    int count = 0;
    foreach ($element in $items) { count++; $body }
    printf("%d items\n", count);
  }
}

macro Decorator $each(Stmt $body, Decl $element, Expr $items) {
  foreach ($element in $items) $body
}

int main(void) {
  int depth = 0;
  Ui ui = { &depth };
  ui.each(int n in [1, 2, 3]) printf("%d\n", n * 2);
  $each(String s in %("a" "b")) puts(s.upper());
  List rows = %((1 "x") (2 "y"));
  $each(List row in rows) printf("%d\n", row.car().int());
  return 0;
}
