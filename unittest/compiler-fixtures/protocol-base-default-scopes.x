#include "x2c.x"

typedef struct Meters {
  double value;
} *Meters;

typedef struct Feet {
  double value;
} *Feet;

protocol Meters(T) {
  double T.magnitude(T);
}

Meters Feet.meters(Feet value) {
  Meters result = Scope.malloc(sizeof(struct Meters));
  result.value = value.value / 2.0;
  return result;
}

Feet Meters.feet(Meters value) {
  Feet result = Scope.malloc(sizeof(struct Feet));
  result.value = value.value * 2.0;
  return result;
}

double Meters.magnitude(Meters value) {
  return value.value;
}

protocol Meters(Feet);

/* Feet omits magnitude, so each call below uses the generated
   base-default binding. The two separate function bodies prove the
   binding survives the expression scope that first resolved it. */
static double first_reading(Feet value) {
  return value.magnitude();
}

static double second_reading(Feet value) {
  return value.magnitude();
}

int main(void) {
  Feet feet = Scope.malloc(sizeof(struct Feet));
  feet.value = 3.0;
  printf("%.1f %.1f\n", first_reading(feet), second_reading(feet));
  return 0;
}
