#include "x2c.x"

meta static void template_noop(void) { }
macro Statement $template_void() => { $template_noop(); }
meta static int twice(int n) { return n * 2; }
meta static List keep_code(List code) { return code; }
meta static int nested(int n) { return $twice(n) + 1; }
meta static int count_values(List values) { return values.len(); }
macro Expression $identity(Expr $value) => ($keep_code($value))

meta static int collision(int n) { return n + 1; }
macro Expression $collision(Expr $value) => ($value + 90)
meta static int expression_macro(int n) { return $collision(n); }

macro Unit $make_function(Name $name, Expr $result) => {
  int $name(void) { return $result; }
}
meta static List build_function(String name, int n) {
  List node = $make_function(name, n * 2);
  return %($node);
}
macro Unit $make_answer() => { $build_function("answer", 21)... }
$make_answer();

meta static List template_parts(List value) { return value; }
macro Unit $function_template(
  Type $spec, Name $name, Expr $params, Expr $items) => {
  $spec $name($template_parts($params)...) {
    $template_parts($items)...
  }
}
meta static List template_build(void) {
  List spec = %(int);
  List params = %((param (int) (bind ("x") ())));
  List items = %((return (int) (expr (int) (ident ("x")))));
  List node = $function_template(spec, "echo", params, items);
  return %($node);
}
macro Unit $build_echo() => { $template_build()... }
$build_echo();

int main(int argc, char **argv) {
  (void) argv;
  $template_noop();
  $template_void();
  int x = argc + 5;
  List values = %(4 5);
  List same = $identity(values);
  printf("%d %d %d\n", $twice(3 + 4), $identity(x + 2), $nested(5));
  printf("%d %d %d\n", $collision(1), collision(1), $expression_macro(1));
  printf("%d %d %d %d\n", answer(), echo(42),
    $count_values(%(1 2 3)), same.len());
  return 0;
}
