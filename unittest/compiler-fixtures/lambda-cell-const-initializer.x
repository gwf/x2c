#include "x2c.x"

/* A const local, a struct with a const member, and a const pointer shared
   by reference initialize their cells instead of assigning them. */
typedef struct { const int id; int uses; } Tag;
typedef struct { int x, y; } Point;

static Point origin(void) => (Point){3, 4};

int main(void) {
  auto {
    const int k = 42;
    Func read = %!() using &k => k;
    const double half = 0.5;
    Func scaled = %!() using &half => half * 4;
    Tag tag = {7, 0};
    Func use = %!() using &tag => tag.uses += tag.id;
    use();
    use();
    const char *name = "cell";
    Func first = %!() using &name => name[0];
    const Point p = origin();
    Func sum = %!() using &p => p.x + p.y;
    const Var v = 9;
    Func boxed = %!() using &v => v;
    int total = 0;
    for (const int step = 2; total < 6; total += step) {
      Func seen = %!() using &step => step;
      total += seen().int() - step;
    }
    printf("%d %g %d %c %d %s %d\n", read().int(), scaled().double(),
           tag.uses, (char)first().int(), sum().int(), boxed().repr(), total);
  }
  return 0;
}
