#include "x2c.x"

/* A local shared by reference keeps its declaration's initializer
   conversion in its cell: a Var from a scalar or a List, a struct copy,
   and a for initializer. Scalars, pointers, arrays, and parameters keep
   their values too. */
typedef struct { int x, y; } Point;

static int moved(Point p) {
  Func f = %!() using &p => p.x += 10;
  f();
  return p.x;
}

int main(void) {
  auto {
    Var count = 5;
    Func bump = %!() using &count => count = count + 1;
    bump();
    Var ratio = 2.5;
    Func half = %!() using &ratio => ratio;
    List items = %(a b);
    Var list = items;
    Func listed = %!() using &list => list;
    printf("%s %s %s\n", count.repr(), half().repr(), listed().repr());
    Point p = {1, 2};
    Point q = p;
    Func gy = %!() using &q => q.y;
    printf("%d %d\n", gy().int(), moved(p));
    int runs = 0;
    for (Var v = 0; v < 2; v = v + 1) {
      Func g = %!() using &v => v;
      runs += g().int() == runs;
    }
    int n = 7;
    int *at = &n;
    char word[5] = "cell";
    Func scalar = %!() using &n => n;
    Func pointer = %!() using &at => *at;
    Func text = %!() using &word => word[1];
    printf("%d %d %d %c\n", runs, scalar().int(), pointer().int(),
           (char)text().int());
  }
  return 0;
}
