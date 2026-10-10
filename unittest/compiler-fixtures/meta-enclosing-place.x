#include "x2c.x"
#include "meta.x"

/* `x2c_enclosing` answers where an invocation stands, and `x2c_place`
   contributes code after the enclosing block item, among the unit's
   support declarations once per key, and in its initialization. */

static int traced = 0;

meta static List trace_after(List value) {
  x2c_place(%(after-statement), $!{ traced++; });
  return value;
}
macro Expression $trace(Expr $value) => $trace_after($value);

meta static List function_name(void) {
  if (x2c_enclosing(<declarator>))
    x2c_diagnostic_fail("an argument has no declarator", %());
  return x2c_literal_string(Code.name(x2c_enclosing(<function>)));
}
macro Expression $here() => $function_name();

meta static List support_counter(String key) {
  List name = x2c_ident(key);
  x2c_place(%(unit-support $key), $!Unit{ static int $name = 1; });
  x2c_place(%(unit-init), $!{ $name += 10; });
  return x2c_expr_ident(name);
}
macro Expression $counter() => $support_counter("counter");

macro Stmt $traced_twice() {
  int inner = $trace(4);
  printf("%d %d\n", inner, traced);
}

int main(void) {
  int first = $trace(1);
  printf("%d %d\n", first, traced);
  printf("%d\n", $trace(2) + traced);
  $traced_twice();
  printf("%d %d\n", traced, $trace(0));
  printf("%s %d %d\n", $here(), $counter(), $counter());
  return 0;
}
