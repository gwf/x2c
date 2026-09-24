#include "x2c.x"

/* Scope.realloc ends the pointer it is given, as Scope.free does, and both
   report storage that no Scope allocator returned. */

int stale(void) {
  int *p = Scope.malloc(4 * sizeof(int));
  int *q = Scope.realloc(p, 8 * sizeof(int));
  p[0] = 1;
  q[0] = 2;
  p = Scope.realloc(q, 16 * sizeof(int));
  int result = p[0];
  Scope.free(p);
  return result + *p;
}

void foreign(void) {
  int x = 0;
  int local[4];
  int *p = &x;
  Scope.free(&x);
  Scope.free(p);
  Scope.free(local);
  char *s = Scope.realloc("abc", 8);
  (void) s;
}

void owned(void) {
  int *p = Scope.malloc(sizeof *p);
  defer Scope.free(p);
  *p = 1;
  p = Scope.realloc(p, 2 * sizeof *p);
  p[1] = 2;
}

int main(void) { return 0; }
