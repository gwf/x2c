#include "x2c.x"

typedef void *Compass;

typedef struct Polar {
  double r;
  double t;
} *Polar;

protocol Compass(T) {
  double T.angle(T);
  double T.radius(T);
}

Compass Polar.compass(Polar p) {
  return (Compass) p;
}

Polar Compass.polar(Compass c) {
  return (Polar) c;
}

double Compass.angle(Compass c) {
  return 0.0;
}

double Compass.radius(Compass c) {
  return 0.0;
}

/* 'radius' matches the protocol template and resolves.  'angle' is a
   homonym with an incompatible signature: exactly one sig-conflict
   diagnostic must be reported, anchored at the adoption row and naming
   both the protocol member's declaration and the conflicting definition,
   while 'radius' still resolves. */
double Polar.radius(Polar p) {
  return p.r;
}

int Polar.angle(Polar p, int q) {
  return (int) p.t + q;
}

protocol Compass(Polar);

int main(void) {
  printf("ok\n");
  return 0;
}
