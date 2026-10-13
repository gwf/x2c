/* A template and a rule quotation keep the file-scope bindings where they
   are written. A caller's local, parameter, or static local of the same
   spelling neither captures the name nor lends it its type, and a `Name`
   argument still reaches the caller's binding. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int leaked = 100;
static String label = "author";

static int helper(void) => 1;

macro Expression $leaked() => leaked;
macro Expression $helped() => helper();
macro Expression $label_length() => label.len();
macro Expression $named(Name $name) => $name;

static int lookup(int unused) => unused;

macro Expression $looked(Expr $step) => lookup($step);

$rewrite($looked)
/* Reads the file-scope `leaked` where the call appears. */
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
