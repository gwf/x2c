#include "x2c.x"
#include "meta.x"

/* Applying a macro value converts a scalar argument as an `expand` row
   does: a Literal hole takes a String, Symbol, or number as its literal,
   and a Name hole takes an Atom's spelling. */
macro Stmt $put(Literal $text) { puts($text); }
macro Stmt $show(Literal $value) { printf("%s\n", ((Var) $value).repr()); }
macro Stmt $declare(Name $name) { int $name = 1; printf("%d\n", $name); }

meta static List applied(void) {
  Macro put = $put;
  Macro show = $show;
  Macro declare = $declare;
  return $(put("hello"), show(<char>), show(42), declare(<alpha>));
}

macro Stmt $apply_all() { @applied() }

int main(void) {
  $apply_all();
  return 0;
}
