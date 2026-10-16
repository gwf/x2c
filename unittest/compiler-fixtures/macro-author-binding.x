/* A template keeps the file-scope binding where it is written for each name
   its `using` list names. A caller's local, parameter, or static local of
   the same spelling neither captures a listed name nor lends it its type.
   An unlisted name, such as the one the rule quotation reads, resolves
   where the code lands, and a `Name` argument reaches the caller's
   binding. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int leaked = 100;
static String label = "author";

static int helper(void) => 1;

macro Expression $leaked() using leaked => leaked;
macro Expression $helped() using helper => helper();
macro Expression $label_length() using label => label.len();
macro Expression $named(Name $name) => $name;

static int lookup(int unused) => unused;

macro Expression $looked(Expr $step) => lookup($step);

$rewrite($looked)
/* Reads whichever `leaked` is visible where the call appears. */
meta Code read_leaked(Code node) {
  return $!int{ leaked };
}

static int macro_read(void) { int leaked = 5; return $leaked() + leaked; }
static int function_read(void) { int helper = 7; return $helped() + helper; }
static int typed_read(void) { int label = 2; return $label_length() + label; }
static int named_read(void) { int leaked = 5; return $named(leaked); }
static int rule_read(int leaked) => lookup(0) + leaked;
static int static_read(void) {
  static int leaked = 3;
  return lookup(0) + leaked;
}

int main(void) {
  printf(
    "%d %d %d %d %d %d\n", macro_read(), function_read(), typed_read(),
    named_read(), rule_read(1), static_read());
  return 0;
}
