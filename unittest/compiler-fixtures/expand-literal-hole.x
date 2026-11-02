#include "x2c.x"

/* A Literal hole lifts each row's String, Symbol, or number to its
   literal, as an Expr hole does. */
int main(void) {
  expand %("hello" <char> 42 2.5)
  macro Stmt(Literal $value) { printf("%s\n", ((Var) $value).repr()); }
  return 0;
}
