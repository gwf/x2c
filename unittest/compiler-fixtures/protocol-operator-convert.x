#include "x2c.x"
#include <stdio.h>

/* A binary operator with one participant operand converts the other
   operand through the declared converter. */
typedef struct Meters { double value; } Meters;

Var Meters.var(Meters m) {
  Meters *boxed = Scope.malloc(sizeof(Meters));
  *boxed = m;
  return Var.new(<meters>, boxed);
}

Meters Var.meters(Var v) => *(Meters *) v.pointer();
Meters double.meters(double value) { Meters m = { value }; return m; }
Meters Meters.add(Meters a, Meters b) { Meters m = { a.value + b.value }; return m; }
Meters Meters.sub(Meters a, Meters b) { Meters m = { a.value - b.value }; return m; }
int Meters.compare(Meters a, Meters b) => a.value < b.value ? -1 : a.value > b.value;
protocol Var(Meters);

int main(void) {
  Meters m = { 3.0 };
  Meters sum = m + 2.0, difference = 10.0 - m;
  printf("%.1f %.1f %d %d\n", sum.value, difference.value, m > 1.0, 5.0 < m);
  return 0;
}
