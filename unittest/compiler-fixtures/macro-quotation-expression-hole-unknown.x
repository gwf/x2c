#include "x2c.x"
#include "meta.x"

/* A `${expression}` hole resolves its names where the quotation is
   written. A name the body declares, or a misspelled one, has no x2c type
   there, and the report names the expression in the braces. */
meta static List body_local(List a) =>
  $!( ({ int v = 1; $a + ${v}; }) );

meta static List misspelled(List a) {
  int count = 2;
  return $!( $a + ${coutn} );
}

int main(void) { return 0; }
