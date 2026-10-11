#include "x2c.x"

#include <stdio.h>

typedef struct Shape { double r; } *Shape;
protocol Shape(T) {
  double T.area(T);
  double T.scale(T, double);
}
double Shape.area(Shape s) => s.r * s.r;
double Shape.scale(Shape s, double k) => s.r * k;

typedef struct Disk { double r; } *Disk;
Shape Disk.shape(Disk d) => (Shape) d;

/** The area of a disk, which its adoption of Shape defines. */
meta double Disk.area(Disk d);

meta protocol Shape(Disk);

int main(void) {
  struct Disk storage = {2.0};
  Disk d = &storage;
  printf("%g %g\n", d.area(), d.scale(3.0));
  return 0;
}
