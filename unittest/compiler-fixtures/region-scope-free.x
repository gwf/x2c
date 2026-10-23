#include "x2c.x"

/* Scope.realloc ends the pointer it is given, as Scope.free does, and both
   report storage that no Scope allocator returned. */

int stale(void) {
  int *p = xmalloc(4 * sizeof(int));
  int *q = xrealloc(p, 8 * sizeof(int));
  p[0] = 1;
  q[0] = 2;
  p = xrealloc(q, 16 * sizeof(int));
  int result = p[0];
  xfree(p);
  return result + *p;
}

void foreign(void) {
  int x = 0;
  int local[4];
  int *p = &x;
  xfree(&x);
  xfree(p);
  xfree(local);
  char *s = xrealloc("abc", 8);
  (void) s;
}

void owned(void) {
  int *p = xmalloc(sizeof *p);
  defer xfree(p);
  *p = 1;
  p = xrealloc(p, 2 * sizeof *p);
  p[1] = 2;
}

int main(void) { return 0; }
