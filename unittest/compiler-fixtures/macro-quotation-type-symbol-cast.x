#include "x2c.x"
#include "meta.x"

/* A Type hole in a quotation spells its type name as a Symbol. */
meta static List cast_var(List v) {
  Type t = %(Var);
  return $!( ($t) $v );
}
macro Expression $var_of(Expr $v) => $cast_var($v);

int main(void) {
  Var v = $var_of(3);
  return v.integer() != 3;
}
