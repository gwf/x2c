#include "x2c.x"

/* A macro's match or catch binder shared by reference keeps the arm's
   binding: the lambda updates the binder, and the caller's same-named
   local stays 77. An arm that shares only an inner local keeps it too. */
macro Stmt $matched(Expr $caller) {
  match (%(5)) {
    case %(?n) if ($caller == 77): {
      Func g = %!() using &n => n = n + 1;
      g();
      printf("match %s %s\n", n.repr(), ($caller).repr());
    }
  }
}

macro Stmt $caught(Expr $caller) {
  try raise %(boom (k 5));
  catch %(boom (k ?n)): {
    Func g = %!() using &n => n = n + 1;
    g();
    printf("catch %s %s\n", n.repr(), ($caller).repr());
  }
}

macro Stmt $inner(Expr $caller) {
  match (%(5)) {
    case %(?n): {
      Var m = n;
      Func g = %!() using &m => m = m + 1;
      g();
      printf("inner %s %s %s\n", n.repr(), m.repr(), ($caller).repr());
    }
  }
}

int main(void) {
  auto {
    Var n = 77;
    $matched(n);
    $caught(n);
    $inner(n);
    printf("caller %s\n", n.repr());
  }
  return 0;
}
