#include "x2c.x"
#include "meta.x"

/* A Macro value applied in a quotation's hole expands where a top-level
   `$(...)` slot lands the quotation, in an argument or an initializer. */
macro Expression $sum(Expr $a, Expr $b) => $a + $b;

meta static List scaled(void) {
  Macro s = $sum;
  return $!( ${s(1, 2)} * 10 );
}

meta static List held(void) {
  Macro s = $sum;
  List inner = s(3, 4);
  return $!( $inner * 10 );
}

int main(void) {
  int v = $(scaled);
  printf("%d %d %d\n", $(scaled), v, $(held));
  return 0;
}
