#include "x2c.x"
#include "meta.x"

/* A type name in a Type List is a String; only C type keywords are
   Symbols. A typed quotation's type spells its name as a Symbol. */
meta static List typed_string(List v) {
  Type t = %(String);
  return $!($t){ $v };
}
macro Expression $string_of(Expr $v) => $typed_string($v);

int main(void) {
  String s = $string_of("q");
  return s.len() != 1;
}
