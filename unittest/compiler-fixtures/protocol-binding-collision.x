#include "x2c.x"

typedef struct Cartesian {
  double x;
} *Cartesian;

typedef struct Polar {
  double r;
} *Polar;

protocol Cartesian(T) {
  double T.angle(T);
}

Cartesian Polar.cartesian(Polar value) {
  Cartesian result = Scope.malloc(sizeof(struct Cartesian));
  result.x = value.r;
  return result;
}

Polar Cartesian.polar(Cartesian value) {
  Polar result = Scope.malloc(sizeof(struct Polar));
  result.r = value.x;
  return result;
}

double Cartesian.angle(Cartesian value) {
  return value.x;
}

int Polar.angle(Polar value) {
  return (int) value.r;
}

protocol Cartesian(Polar);

int main(void) {
  return 0;
}
