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
  return 0;
}
