#include "x2c.x"
#include "meta.x"

/* Applying a macro value lifts a String, Symbol, or number in a Literal
   hole to its literal, as it does in an Expr hole. */
macro Stmt $show(Literal $value) { printf("%s\n", ((Var) $value).repr()); }

meta static List shown(void) {
  Macro show = $show;
  return $(show("hello"), show(<char>), show(42));
}

macro Stmt $show_all() { @shown() }

int main(void) {
  $show_all();
  return 0;
}
