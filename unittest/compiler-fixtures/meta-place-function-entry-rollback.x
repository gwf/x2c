#include "x2c.x"
#include "meta.x"

/* A failed expansion leaves none of its function-entry code behind, and
   code placed at function entry needs an enclosing function. The entry
   code here would be rejected if it were ever bound. */

meta static List place_entry(List value) {
  x2c_place(%(function-entry), $!{ (void) (value is int); });
  return value;
}
macro Expression $entry(Expr $value) => $place_entry($value);

// The placement succeeds, and then binding the expansion's result fails.
macro Expression $failing(Expr $value) => $entry($value) is int;

static int failed(int value) {
  return $failing(value);
}

static int follows(int value) {
  return value + 1;
}

static int outside = $entry(1);

int main(void) {
  return follows(1);
}
