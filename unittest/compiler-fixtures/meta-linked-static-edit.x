// The selector matches its linked text; its edited static table must run
// in the project meta module instead of reusing the shipped report row.
#include "x2c.x"

meta static Map _error_report_rows = {
  "protocol.tag.var" :
  macro Statement(Expr $c, Expr $origin) {
    puts("edited report");
  },
};

meta static List _error_report_expand(
  List compiler, String key, List arguments) {
  Map rows = _error_report_rows;
  Var value = rows[key];
  if (value is void)
    x2c_diagnostic_fail(%"unknown error report '$key'", %());
  Macro selected = value;
  if (arguments.len() + 1 != selected.assoc(<parameters>).list().len())
    x2c_diagnostic_fail(%"wrong argument count for error report '$key'", %());
  return %(${Macro_apply(selected, %($compiler @arguments))});
}

macro Statement $report(Expr $compiler, Literal $key, Expr $arguments...) {
  $(_error_report_expand $compiler (x2c.literal.value $key) $arguments)...
}

int main(void) {
  $report(NULL, "protocol.tag.var", NULL);
  return 0;
}
