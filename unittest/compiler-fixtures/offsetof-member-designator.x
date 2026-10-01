#include <stddef.h>
#include <stdio.h>

// `offsetof` takes a type name and a C member designator: a field, then any
// `.field` and `[index]` selections.
struct In { char c; int v[4]; };
struct P { int a; double b; struct In in[3]; };
typedef struct { char tag; long value; } Q;

int main(void) {
  int i = 1;
  size_t n = offsetof(struct P, b);
  printf("%zu %zu\n", n, offsetof(Q, value));
  printf("%d %d\n",
         offsetof(struct P, in[2].v[1]) ==
           offsetof(struct P, in) + 2 * sizeof(struct In) +
           offsetof(struct In, v) + sizeof(int),
         offsetof(struct P, in[i].c) == offsetof(struct P, in[1]));
  return 0;
}
