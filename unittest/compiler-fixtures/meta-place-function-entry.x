#include "x2c.x"
#include "meta.x"

/* `x2c_place(%(function-entry), code)` puts code at the entry of the
   enclosing function, after its parameters bind and before its first
   statement, in placement order. `x2c_enclosing(<function>)` answers that
   function from any depth of its body. */

meta static List note_entry(List value, List label) {
  List count = x2c_function_parameter(x2c_enclosing(<function>), "count");
  x2c_place(
    %(function-entry), $!{ printf("entry %s count %d\n", $label, $count); });
  return value;
}
macro Expression $entered(Expr $value, Expr $label) =>
  $note_entry($value, $label);

meta static List function_name(void) =>
  x2c_literal_string(x2c_function_name(x2c_enclosing(<function>)));
macro Expression $here() => $function_name();

static int sum(int count) {
  printf("first statement\n");
  int total = 0;
  for (int i = 0; i < count; i++) {
    if (i == 1) {
      total += $entered(i, "a");
      printf("inside %s\n", $here());
    }
    else total += i;
  }
  {
    total += $entered(10, "b");
  }
  return total;
}

static void none(void) {
  printf("%s has no entry code\n", $here());
}

int main(void) {
  printf("%d\n", sum(3));
  none();
  return 0;
}
