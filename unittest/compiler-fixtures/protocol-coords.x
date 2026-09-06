#include "x2c.x"
#include <math.h>

typedef struct Cartesian {
  double x;
  double y;
} *Cartesian;

typedef struct Polar {
  double r;
  double t;
} *Polar;

protocol Cartesian(T) {
  double T.magnitude(T);
  double T.angle(T);
}

Cartesian Cartesian.new(double x, double y) {
  Cartesian value = Scope.malloc(sizeof(struct Cartesian));
  value.x = x;
  value.y = y;
  return value;
}

Polar Polar.new(double r, double t) {
  Polar value = Scope.malloc(sizeof(struct Polar));
  value.r = r;
  value.t = t;
  return value;
}

Cartesian Polar.cartesian(Polar value) {
  return Cartesian.new(
    value.r * cos(value.t),
    value.r * sin(value.t)
  );
}

Polar Cartesian.polar(Cartesian value) {
  return Polar.new(
    sqrt(value.x * value.x + value.y * value.y),
    atan2(value.y, value.x)
  );
}

double Cartesian.magnitude(Cartesian value) {
  return sqrt(value.x * value.x + value.y * value.y);
}

double Cartesian.angle(Cartesian value) {
  return atan2(value.y, value.x);
}

double Polar.magnitude(Polar value) {
  return value.r;
}

protocol Cartesian(Polar);

int main(void) {
  Cartesian cartesian = Cartesian.new(3.0, 4.0);
  Polar polar = Polar.new(5.0, 0.0);
  printf("%.1f %.1f %.1f\n",
         cartesian.magnitude(),
         polar.magnitude(),
         polar.angle());
  return 0;
}
