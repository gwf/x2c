#include "x2c.x"

/* Owner unit: declares an ordinary protocol Meters(T) whose member
   magnitude has a base default (Meters.magnitude). Feet conforms via its
   converter pair but omits magnitude, so Feet.magnitude is a base-default
   member whose generated binding (Feet_magnitude) is emitted here.

   The two reader functions dot-call feet.magnitude() twice: the first
   pins same-invocation resolution, the second pins that a second dot
   call in a distinct function body still resolves the base-default row
   without relying on a phantom binding surviving an expression scope. */

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

double owner_first_reading(Feet value) {
  return value.magnitude();
}

double owner_second_reading(Feet value) {
  return value.magnitude();
}
