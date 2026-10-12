/* Code placed at a function's entry lowers with the function still
   entered, so a rule it reaches can place at the entry too, ahead of it.
   A finalizer that lands in its function places at that function's entry. */

#include "x2c.x"
#include "rewrite.x"
#include "meta.x"

#include <stdio.h>

static int tally(int step) => step;
static int mark(int step) => step;

macro Expression $tallied(Expr $step) => tally($step);
macro Expression $marked(Expr $step) => mark($step);

$rewrite($tallied)
/* Places a call the second rule rewrites. */
meta Code place_mark(Code code) {
  x2c_place(%(function-entry), $!{ printf("entry mark %d\n", mark(1)); });
  return code;
}

$rewrite($marked)
/* Places again while the first placement lowers. */
meta Code place_note(Code code) {
  x2c_place(%(function-entry), $!{ printf("entry note\n"); });
  return code;
}

static int run(int n) {
  printf("body\n");
  return tally(n);
}

/* A finalizer that may return lands in its function. */
static int landing(int n) {
  printf("landing body\n");
  {
    defer {
      printf("landing finalizer %d\n", tally(n));
      if (n < 0) return -1;
    }
    printf("landing block\n");
  }
  return n;
}

int main(void) {
  printf("%d\n", run(3));
  printf("%d\n", landing(2));
  return 0;
}
