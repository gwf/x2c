#include <stdio.h>
typedef struct Point { int x; } Point;
typedef struct Chain { int n; } ChainBase;
typedef struct Chain ChainOther;
typedef ChainBase Chain;
static int Point.get(Point *p) => p.x;
static int Point.twice(Point p) => p.x * 2;
static int Point.read(Point &p) => p.x;
static int struct_get(Point p) => 99;
typedef union Num { int i; float f; } Num;
static int Num.whole(Num n) => n.i;
static int Num.read(Num &n) => n.i;
typedef struct Holder { struct Point p; Point q; union Num n; } Holder;
typedef struct size_s { int w; } Size;
static int Size.width(Size *s) => s.w;
static int Size.read(Size &s) => s.w;
static int Chain.read(Chain &value) => value.n;

int main(void) {
  Holder h = {{3}, {4}, {.i = 7}};
  struct Point local = {9};
  struct size_s size = {5};
  struct Chain chain = {8};
  printf("%d %d %d %d %d %d %d\n", h.p.get(), h.q.get(), h.p.twice(),
         h.n.whole(), local.get(), local.twice(), size.width());
  printf("%d %d %d %d\n", local.read(), h.n.read(), size.read(),
    chain.read());
  return 0;
}
