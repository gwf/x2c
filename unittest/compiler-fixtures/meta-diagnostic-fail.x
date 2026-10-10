/* x2c_diagnostic_fail stops the expansion at the invocation from any meta
   call position: an expression, a void statement, and a nested helper. */
#include "x2c.x"
#include "meta.x"

meta static List one_word(Source node) {
  String text = Code.source_text(node);
  if (text.contains(" "))
    x2c_diagnostic_fail("this argument must be one word", %());
  return $!String{ $text };
}

meta static void require_word(Source node) {
  if (Code.source_text(node).contains(" "))
    x2c_diagnostic_fail("this statement needs one word", %());
}

meta static void fail_inner(String text) {
  x2c_diagnostic_fail("the nested helper failed", %("text: $text"));
}

meta static List fail_outer(Source node) {
  fail_inner(Code.source_text(node));
  return $!String{ ${"unreached"} };
}

macro Expression $probe.word(Expr $value) => $one_word($value);
macro Stmt $probe.check(Expr $value) {
  $require_word($value);
}
macro Expression $probe.nested(Expr $value) => $fail_outer($value);

int seconds = 90;

String word(void) => $probe.word(seconds * 2);

void check(void) {
  $probe.check(seconds * 2);
}

String nested(void) => $probe.nested(seconds);
