#include "x2c.x"

/* A compile-time read through a pointer that Scope.realloc moved, and a
   free of storage no Scope allocator returned, are errors. */

meta int read_after_realloc(void) {
  int *p = Scope.calloc(2, sizeof(int));
  int *q = Scope.realloc(p, 4 * sizeof(int));
  q[3] = 1;
  return p[0];
}

meta int free_local(void) {
  int x = 1;
  Scope.free(&x);
  return x;
}

int main(void) { return 0; }
