/*  protocols.x -- protocol declaration, adoption, and base defaults */


typedef struct Meters {
  long value;
} *Meters;

typedef struct Km {
  long value;
} *Km;

typedef struct Cm {
  long value;
} *Cm;

protocol Meters(T) {
  long T.magnitude(T);
  String T.describe(T);
}

long Meters.magnitude(Meters value) {
  return value.value;
}

String Meters.describe(Meters value) {
  return %"${value.value} m";
}

/* Total forward views: every Km or Cm is a valid Meters. */
Meters Km.meters(Km value) {
  Meters result = Scope.malloc(sizeof(struct Meters));
  result.value = value.value * 1000;
  return result;
}

Meters Cm.meters(Cm value) {
  Meters result = Scope.malloc(sizeof(struct Meters));
  result.value = value.value / 100;
  return result;
}

/* Km overrides describe; magnitude still forwards to the base. */
String Km.describe(Km value) {
  return %"${value.value} km";
}

protocol Meters(Km);

/* Cm implements nothing itself; a static adoption keeps the
   conformance local to this translation unit. */
static protocol Meters(Cm);

int main(void) {
  Scope.retain();

  Km trip = Scope.malloc(sizeof(struct Km));
  trip.value = 3;
  Cm pencil = Scope.malloc(sizeof(struct Cm));
  pencil.value = 1800;

  printf("%s is %ld m\n", trip.describe(), trip.magnitude());
  printf("%s is %ld m\n", pencil.describe(), pencil.magnitude());

  Scope.release();
  return 0;
}
