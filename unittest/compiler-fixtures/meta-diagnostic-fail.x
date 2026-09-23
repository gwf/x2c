/* x2c_diagnostic_fail stops the expansion at the invocation from any meta
   call position: an expression, a void statement, and a nested helper. */
#include "x2c.x"
#include "meta.x"

meta static List one_word(Var node) {
  String text = x2c_source_text(node);
  if (text.contains(" "))
    x2c_diagnostic_fail("this argument must be one word", %());
  return x2c_literal_string(text);
}

meta static void require_word(Var node) {
  if (x2c_source_text(node).contains(" "))
    x2c_diagnostic_fail("this statement needs one word", %());
}

meta static void fail_inner(String text) {
  x2c_diagnostic_fail("the nested helper failed", %("text: $text"));
}

meta static List fail_outer(Var node) {
  fail_inner(x2c_source_text(node));
  return x2c_literal_string("unreached");
}

macro Expression $probe.word(Expr $value) => $one_word($value);
macro Statement $probe.check(Expr $value) {
  $require_word($value);
}
macro Expression $probe.nested(Expr $value) => $fail_outer($value);

int seconds = 90;

String word(void) => $probe.word(seconds * 2);

void check(void) {
  $probe.check(seconds * 2);
}

String nested(void) => $probe.nested(seconds);
