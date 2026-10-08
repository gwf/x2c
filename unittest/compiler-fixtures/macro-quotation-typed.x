#include "x2c.x"
#include "meta.x"

/* `$!T{ expression }` and `$!(T){ expression }` build `(expr T CONTENT)`
   where they are written. They bind nothing: inner nodes keep the
   placeholder type, free names stay names, and holes take the values a
   rebuild gives them. */

typedef struct Call { List callee; Type result; } Call;

/* The printed form without the spaces repr leaves at its line breaks. */
static void show(List code) {
  printf("%s\n", code.repr().replace(" \n", "\n"));
}

static void built(void) {
  List lhs = %(expr (int) (ident "a"));
  List items = %((expr (int) (literal (int) "1"))
                 (expr (int) (literal (int) "2")));
  Type type = %(double);
  int negative = -3;
  String label = "hi";
  Symbol op = <+>;
  List binding = %(binding 7 "count");
  Call d = {.callee = %(expr () (ident "g")), .result = %(long)};
  /* A type name; syntax holes keep their syntax. */
  show($!int{ !equal($lhs, other) });
  /* A type of several words takes parentheses; a sequence hole splices
     its items. */
  show($!(unsigned long){ f($lhs, @items) });
  /* So does a type spelled like a kind name. */
  show($!(Type){ $lhs });
  /* A Type local names the type and fills a type position; an int is a
     literal. */
  show($!($type){ ($type) $negative });
  /* A String and a Symbol are literals. */
  show($!(char *){ g($label, $op) });
  /* A binding is a reference to it. */
  show($!($type){ $binding });
  /* `${...}` holes compute the type and the code. */
  show($!(${d.result}){ ${d.callee}(@items) });
}

/* In a `meta` function the typed code returns to the compiler, which
   binds its free names where it lands. */
meta static List doubled(List value) {
  List twice = $!double{ $value * 2 };
  return twice;
}
meta static List type_of(List value) =>
  x2c_literal_string($!double{ $value * 2 }.cadr().repr());
meta static List plus_total(List value) {
  List total = x2c_ident("total");
  return $!int{ $total + $value };
}
macro Expression $twice(Expr $v) => $doubled($v);
macro Expression $typed(Expr $v) => $type_of($v);
macro Expression $plus(Expr $v) => $plus_total($v);

meta static List min_width(void) {
  int value = INT_MIN;
  return $!(unsigned long){ sizeof($value) };
}
macro Expression $minimum_width() => $min_width();

int main(void) {
  built();
  int total = 40;
  printf("%g %s %d\n", $twice(1.5), (char *) $typed(1.5), $plus(2));
  printf("%d\n", $minimum_width() == sizeof(int));
  return 0;
}
