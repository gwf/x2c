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
macro Statement $choose(Expr $subject, Statement $arms...) {
  $numbered($subject, $arms)...
}

meta static List doubled(List value) => $!( $value + $value );
macro Expression $twice(Expr $value) => $doubled($value);

meta static List wrapped(List items) {
  List block = $!{ { printf("begin\n"); $items... printf("end\n"); } };
  return %($block);
}
macro Statement $around(Statement $items...) { $wrapped($items)... }

meta static List getter(String name, int value) {
  List unit = $!Unit{ static int $name(void) { return $value; } };
  return %($unit);
}
macro Unit $define_getter(Name $name, Literal $value) {
  $getter($name, $value)...
}

$define_getter(answer, 42);

int main(void) {
  int pick = 1;
  $choose(pick, printf("zero\n");, printf("one\n");, printf("two\n"););
  $around(printf("a\n");, printf("b\n"););
  printf("%d %d\n", $twice(21), answer());
  return 0;
}
