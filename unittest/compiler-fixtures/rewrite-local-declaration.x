/* A transform-time replacement that declares a name with unbound syntax
   declares it in its own function: a quotation another rule lowers in
   another function still reads the file-scope name. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static String leaked = "global";

static int lookup(int unused) => unused;

$rewrite(%(dstrdecl ? (targets *) ?))
/* Declares each target as 7 with unbound syntax. */
meta Code redeclare(Code node) {
  return %(declare (int)
    (bindings
      (op = (bind ("leaked") ()) (expr (int) (literal (int) "7")))
      (op = (bind ("other") ()) (expr (int) (literal (int) "7")))));
}

macro Expression $looked(Expr $step) => lookup($step);

$rewrite($looked)
/* Reads `leaked` where the call appears. */
meta Code read_leaked(Code node) {
  return $!int{ (int) leaked.len() };
}

static int first(void) {
  int (leaked, other) = %(1 2);
  return leaked + other;
}

static int second(void) => lookup(0);

int main(void) {
  printf("%d %d\n", first(), second());
  return 0;
}
