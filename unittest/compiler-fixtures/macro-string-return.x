#include "x2c.x"

/* A macro body is parsed outside any function, so its `return` records no
   type annotation. The enclosing function must still supply one, or the
   returned value crosses to String or Var unconverted. */

macro Statement $probe.string_return() => { return "NaN"; }

macro Statement $probe.var_return() => { return 42; }

static String from_macro(void) { $probe.string_return(); }

static Var boxed_from_macro(void) { $probe.var_return(); }

static String from_source(void) { return "NaN"; }

int main(void) {
  printf("%d %d %d\n", from_macro().len(), from_source().len(),
         boxed_from_macro().int());
  return 0;
}
