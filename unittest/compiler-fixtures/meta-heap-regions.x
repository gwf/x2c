#include "x2c.x"

/* A compile-time read through a pointer that Scope.realloc moved, and a
   free of storage no Scope allocator returned, are errors. */

meta int read_after_realloc(void) {
  int *p = xcalloc(2, sizeof(int));
  int *q = xrealloc(p, 4 * sizeof(int));
  q[3] = 1;
  return p[0];
}

meta int free_local(void) {
  int x = 1;
  xfree(&x);
  return x;
}

int main(void) { return 0; }

meta Array updated_array(void) {
  auto {
    Array a = [];
    return a.update_n(0);
  }
  return NULL;
}

meta Map updated_map(void) {
  auto {
    Map m = {};
    return m.update_n(0);
  }
  return NULL;
}

meta Map merged_with(Map other) {
  auto {
    Map m = {};
    return m.merge_with(other, NULL);
  }
  return NULL;
}
