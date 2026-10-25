#include "x2c.x"

/* `$(expression)` inserts one value and `@(expression)` splices a List in
   quoted data; a String inserts with `$(expression)` only. */
static int count = 0;
static int next(int n) {
  printf("next %d\n", n);
  count++;
  return n;
}

int main(void) {
  int x = 7;
  List xs = %(7 8);
  printf("%s\n", %(head $x).repr());
  printf("%s\n", %(head $(x)).repr());
  printf("%s\n", %(head ($x)).repr());
  printf("%s\n", %(head $($(x))).repr());
  printf("%s\n", %(head $(xs)).repr());
  printf("%s\n", %(head @(xs)).repr());
  printf("%s\n", %(head @($(1, 2)) @([3, 4])).repr());
  // A grouped insertion holds one C expression, so a comma is an operator.
  printf("%s\n", %(head $(next(0), next(1)) $(next(2) + 1)).repr());
  printf("%s\n", %[$(x + 1), $x, (a $(x)), {k: $(x)}].repr());
  printf("%s\n", %{$(%"k$x"): $(x * 2), b: (c @(xs))}.repr());
  printf("%s\n", %"answer: $(x * 6), $x(x), $$(x), $(%"in $(next(3))")");
  printf("%s\n", %"call: $(((x)) + (1))");
  printf("count %d\n", count);
  return 0;
}
