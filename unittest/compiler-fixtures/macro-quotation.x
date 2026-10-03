#include "x2c.x"
#include "meta.x"

/* A quotation is an anonymous macro applied where it is written. Each
   `$name` in its body names a visible local, and its first position gives
   the hole its kind: a statement, an expression, a name, or a `...`
   sequence. */
meta static List numbered(List subject, List arms) {
  Array cases = [];
  int index = 0;
  foreach (List arm, arms) {
    cases.push($!{ if ($subject == $index) $arm });
    index++;
  }
  return cases.list_free();
}
macro Stmt $choose(Expr $subject, Stmt $arms...) {
  $numbered($subject, $arms)...
}

meta static List doubled(List value) => $!( $value + $value );
macro Expression $twice(Expr $value) => $doubled($value);

meta static List wrapped(List items) {
  List block = $!{ { printf("begin\n"); $items... printf("end\n"); } };
  return %($block);
}
macro Stmt $around(Stmt $items...) { $wrapped($items)... }

meta static List getter(String name, int value) {
  List unit = $!Unit{ static int $name(void) { return $value; } };
  return %($unit);
}
macro Unit $define_getter(Name $name, Literal $value) {
  $getter($name, $value)...
}

$define_getter(answer, 42);

/* Each local fills its own hole, a sequence before a scalar included. */
meta static List tail(List items, int value) =>
  $!{ $items... printf("%d\n", $value); };
macro Stmt $show(Stmt $items...) { $tail($items, 7)... }

/* A hole at the top level of `({ ... })` makes it a statement expression;
   a comma would make it data, and one datum states its type. */
meta static List both_then(List first, List second) =>
  $!( ({ $first $second }) );
macro Expression $sequenced(Stmt $first, Stmt $second) =>
  $both_then($first, $second);
macro Expression $grouped_pair(Stmt $first, Stmt $second) =>
  ({ $first $second });
typedef struct { int x; } Boxed;
macro Expression $boxed(Expr $value) => ((Boxed){ $value });

/* A quotation inside syntax built by hand expands where it is resolved. */
static void report(int value) { printf("%d\n", value); }
meta static List reported(List v) {
  List bumped = $!( $v + 1 );
  return x2c_expr_call(x2c_expr_ident(x2c_ident("report")), %($bumped));
}
macro Expression $report_next(Expr $v) => $reported($v);
meta static List doubled_local(List v) {
  List twice = $!( $v * 2 );
  List declaration = x2c_decl_make(%(int), "twice", twice);
  List shown = $!{ report(twice); };
  return %($declaration $shown);
}
macro Stmt $show_twice(Expr $v) { $doubled_local($v)... }

/* A meta call spliced in a quotation runs where the quotation expands; a
   `$name` hole names only a local. */
meta static List each_print(List values) {
  Array rows = [];
  foreach (List v, values) rows.push($!{ printf("%d\n", $v); });
  return rows.list_free();
}
meta static List bracketed(List values) =>
  $!{ { printf("begin\n"); $each_print($values)... printf("end\n"); } };
macro Stmt $print_all(Expr $values...) { $bracketed($values)... }

/* A sequence hole splices Array and Map elements and braced initializer
   elements, in templates and quotations alike. */
meta static List array_of(List items) => $!( %[$items...] );
macro Expression $quoted_array(Expr $items...) => $array_of($items);
meta static List map_of(List rows) => $!( %{${$rows...}} );
macro Expression $quoted_map(Entry $rows...) => $map_of($rows);
typedef struct { int a, b, c; } Triple;
macro Expression $triple(Expr $first, Expr $rest...) => (Triple){ $first, $rest... };
meta static List triple_of(List items) => $!( (Triple){ $items... } );
macro Expression $quoted_triple(Expr $items...) => $triple_of($items);
macro Stmt $declare_triple(Name $name, Expr $items...) {
  Triple $name = { $items... };
}

/* Field and Enumerator quotations splice their rows into an aggregate. */
meta static List quoted_fields(void) {
  List fields = $!Field{ int a; };
  return %($fields);
}
macro Unit $quoted_record(Name $name) {
  typedef struct $name { $quoted_fields()... double b; } $name;
}
$quoted_record(Pair);
meta static List quoted_enumerators(void) {
  List enumerators = $!Enumerator{ RED, GREEN };
  return %($enumerators);
}
macro Unit $quoted_enum(Name $name, Name $last) {
  enum $name { $quoted_enumerators()..., $last };
}
$quoted_enum(Color, BLUE);

int main(void) {
  int pick = 1;
  $choose(pick, printf("zero\n");, printf("one\n");, printf("two\n"););
  $around(printf("a\n");, printf("b\n"););
  printf("%d %d\n", $twice(21), answer());
  $show(printf("start\n"););
  int total = 0;
  printf("%d\n", $sequenced(total += 2;, total * 10;));
  (void)$grouped_pair(total += 3;, total += 4;);
  printf("%d %d\n", total, $boxed(5).x);
  (void)$report_next(41);
  $show_twice(21);
  $print_all(1, 2);
  printf("%s %s\n", $quoted_array(1, 2).repr(), $quoted_map("k": 3).repr());
  $declare_triple(spliced, 7, 8, 9);
  printf("%d %d %d\n", $triple(1, 2, 3).c, $quoted_triple(4, 5, 6).c,
         spliced.c);
  Pair pair = { 3, 4.5 };
  printf("%d %.1f %d\n", pair.a, pair.b, BLUE);
  return 0;
}
