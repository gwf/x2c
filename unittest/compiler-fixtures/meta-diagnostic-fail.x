/* x2c_diagnostic_fail stops the expansion at the invocation from any meta
   call position: an expression, a void statement, and a nested helper. */
#include "x2c.x"
#include "meta.x"

$(import "meta-diagnostic-fail.xmacro")

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
