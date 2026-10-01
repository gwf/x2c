#include <stdio.h>
typedef struct Point { int x; } Point;
static int Point.get(Point *p) => p.x;
static int Point.twice(Point p) => p.x * 2;
typedef union Num { int i; float f; } Num;
static int Num.whole(Num n) => n.i;
typedef struct Holder { struct Point p; Point q; union Num n; } Holder;
int main(void) {
  Holder h = {{3}, {4}, {.i = 7}};
  struct Point local = {9};
  printf("%d %d %d %d %d %d\n", h.p.get(), h.q.get(), h.p.twice(),
         h.n.whole(), local.get(), local.twice());
  return 0;
}
