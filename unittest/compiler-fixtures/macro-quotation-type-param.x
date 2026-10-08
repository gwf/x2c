#include "x2c.x"
#include "meta.x"

/* `$!Type{ type-name }` builds a type written as a cast writes it, and
   `$!Param{ parameter }` builds one parameter. `Type` and `Param` after
   `$!` name these kinds, not typed quotations. A `Type` local or a
   `${...}` hole of type `Type` stands for a type or for the base a
   declarator modifies, and a parameter takes its name from a hole. */

typedef struct Point { int x; int y; } Point;

meta static Type point_type(void) => $!Type{ Point };

meta static String types(void) {
  Type point = $!Type{ Point };
  List x = x2c_ident("x");
  List shown = %(
    ${$!Type{ unsigned long * }}
    ${$!Type{ const $point * }}
    ${$!Type{ int (*)($point *) }}
    ${$!Type{ $point }}
    ${$!Type{ ${point_type()} ** }}
    ${$!Type{ int (int) }}
    ${$!Type{ String }}
    ${$!Param{ double $x }}
    ${$!Param{ $point *$x }}
    ${$!Param{ double *${x2c_ident("grad")} }}
    ${$!Param{ int (*$x)(int) }}
  );
  Array lines = [];
  foreach (List item, shown) lines.push(item.repr());
  return "\n".join(lines);
}

/* `name(double x0, ..., double xN)` returns the sum of its arguments. */
meta static List sum_function(String name, int count) {
  Array params = [];
  List total = $!( 0.0 );
  for (int i = 0; i < count; i++) {
    List x = x2c_ident(%"x$i");
    params.push($!Param{ double $x });
    total = $!( $total + $x );
  }
  List declared = params.list_free();
  List function = $!Unit{ double $name(@declared) { return $total; } };
  return %($function);
}

macro Unit $define_sum(Literal $name, Literal $count) {
  @sum_function($name, $count)
}

$define_sum("sum3", 3);

int main(void) {
  printf("%s\n", $types());
  printf("%g\n", sum3(1.0, 2.0, 3.5));
  return 0;
}
