#include "x2c.x"
#include "meta.x"

/* A `${expression}` hole in a quotation inserts a value of the function
   that writes the quotation: a field, an element, or a call's result. A
   `Type` value fills a type, and `@{expression}` splices a List. */
typedef struct Call { List callee; List arguments; Type result; } Call;

meta static List scaled_call(List callee, List a, List b) {
  Call d = {.callee = callee, .arguments = %($a $b), .result = %(int)};
  return $!( ({
    ${d.result} value = ${d.callee}(@{d.arguments});
    value * ${d.arguments.len()};
  }) );
}
macro Expression $scaled(Expr $f, Expr $a, Expr $b) =>
  $scaled_call($f, $a, $b);
static int sum(int a, int b) => a + b;

/* A String or an int value inserts a literal. */
static String labelled(String label, int value) => %"$label=$value";
meta static String greeting(String who) => %"hello $who";
meta static List greeted(String who) =>
  $!( labelled(${greeting(who)}, ${who.len() * 10}) );
macro Expression $greet(Name $who) => $greeted($who);

/* A Unit quotation names its function and returns a computed value. */
typedef struct Getter { String name; int value; } Getter;
meta static List getter(String name, int value) {
  Getter g = {.name = name, .value = value};
  List unit = $!Unit{ static int ${g.name}(void) { return ${g.value * 2}; } };
  return %($unit);
}
macro Unit $define_getter(Name $name, Literal $value) {
  @getter($name, $value)
}
$define_getter(answer, 21);

/* An inner quotation as a hole's value is built first and inserted. */
meta static List outer(List a) {
  List one = %(expr (int) (literal (int) "1"));
  List inner = $!( $a + $one );
  return $!( $inner * ${$!( $a - $one )} );
}
macro Expression $calc(Expr $a) => $outer($a);

/* Each hole is evaluated once, in the order the holes are written, before
   the quotation builds its code. */
meta static List counted(Array log, List value) {
  log.push(value);
  return value;
}
meta static List ordered(List a, List b) {
  Array log = [];
  List built = $!( ${counted(log, a)} - ${counted(log, b)} );
  if (log.len() != 2 || log[0] !== a || log[1] !== b)
    x2c_diagnostic_fail("holes evaluated out of order", %());
  return built;
}
macro Expression $difference(Expr $a, Expr $b) => $ordered($a, $b);

/* After `case`, `${$name(...)}` is still a macro pattern. Inside a List
   literal, `${found}` inserts when the built code runs, and `${${tag}}`
   inserts a value the function computes. */
macro Expression $mul(Expr $a, Expr $b) => $a * $b;
meta static List tagged(String tag, List subject) => $!( ({
  int found = 0;
  match ($subject) case ${$mul(?a, ?b)}: found = 1;
  %(${${tag}} ${found});
}) );
macro Expression $tag(Name $name, Expr $subject) =>
  $tagged($name, $subject);

int main(void) {
  printf("%d\n", $scaled(sum, 2, 5));
  printf("%s %d\n", $greet(world), answer());
  printf("%d\n", $calc(5));
  printf("%d\n", $difference(9, 4));
  List code = %(expr (int) (op * (expr (int) (ident "x"))
                                (expr (int) (literal (int) "7"))));
  printf("%s\n", $tag(alpha, code).repr());
  return 0;
}
