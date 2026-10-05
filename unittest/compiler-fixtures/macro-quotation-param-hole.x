#include "x2c.x"
#include "meta.x"

/* A local holding a parameter fills a parameter hole, alone or as a
   sequence, and the body reads the name it declares through `x2c_ident`,
   directly or in a typed quotation. */
meta static List single(String name) {
  List x = x2c_ident("x");
  List param = %(param (double) (bind ("x") ()));
  return %(${$!Unit{ double $name($param) { return $x * 2; } }});
}

meta static List sequence(String name) {
  List x = x2c_ident("x");
  List params = %((param (double) (bind ("x") ())));
  return %(${$!Unit{ double $name($params...) { return $x * 3; } }});
}

meta static List pair(String name) {
  List x = x2c_ident("x"), y = x2c_ident("y");
  List first = %(param (double) (bind ("x") ()));
  List second = %(param (double) (bind ("y") ()));
  List body = $!double{ $x * $y };
  return %(${$!Unit{ double $name($first, $second) { return $body; } }});
}

macro Unit $make_single(Literal $name) { $single($name)... }
macro Unit $make_sequence(Literal $name) { $sequence($name)... }
macro Unit $make_pair(Literal $name) { $pair($name)... }
$make_single("twice");
$make_sequence("thrice");
$make_pair("product");

int main(void) {
  printf("%g %g %g\n", twice(21.0), thrice(14.0), product(6.0, 7.0));
  return 0;
}
