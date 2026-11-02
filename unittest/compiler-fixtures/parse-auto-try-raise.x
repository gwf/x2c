/*  parse-auto-try-raise.x -- a statement-start `auto` opens a region
    before the contextual words `try` and `raise`, while `auto try = 5`
    still infers a local named `try`.
*/
#include "x2c.x"

static int released;
static void drop(void *value) { released += *(int *) value; }
static int acquire(int value) {
  int *p = Scope.malloc_finalized(sizeof(int), drop);
  *p = value;
  return value;
}

static void limit(int n) {
  if (n > 1) auto raise %(too-big (n $(acquire(n))));
}

int main(void) {
  auto try { acquire(1); }
  finally { printf("finally %d\n", released); }
  printf("after try %d\n", released);
  try { limit(1); limit(4); }
  catch %(too-big (n ?n)): printf("caught %d after %d\n", (int) n, released);
  auto try = 5;
  auto raise = 6;
  printf("locals %d %d\n", try, raise);
  return 0;
}
