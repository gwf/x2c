#include "x2c.x"
#include "meta.x"

/* A local holding `x2c_ident` code fills a declarator and a reference with
   the same exact name, in one quotation or in separately built ones. */
meta static List counted(List value) {
  List total = x2c_ident("total");
  return $!( ({ int $total = $value; $total += 1; $total; }) );
}
macro Expression $next(Expr $value) => $counted($value);

meta static List shared(List value) {
  List name = x2c_ident("shared");
  List declaration = $!{ int $name = $value; };
  List use = $!{ printf("%d\n", $name * 2); };
  return %($declaration $use);
}
macro Stmt $show_doubled(Expr $value) { $shared($value)... }

int main(void) {
  printf("%d\n", $next(41));
  $show_doubled(21);
  return 0;
}
