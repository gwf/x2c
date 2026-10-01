/*  protocols.x -- protocol declaration, adoption, and base defaults */


/* Each magnitude is an ordinary record value initialized by its class
   constructor. Protocols share the magnitude and display operations. */
class Meters { long value; };
class Km { long value; };
class Cm { long value; };

protocol Meters(T) {
  long T.magnitude(T);
  String T.describe(T);
}

long Meters.magnitude(Meters value) => value.value;

String Meters.describe(Meters value) => %"${value.value} m";

/* Total forward views: every Km or Cm is a valid Meters. */
Meters Km.meters(Km value) => Meters.new(value.value * 1000);

Meters Cm.meters(Cm value) => Meters.new(value.value / 100);

/* Km overrides describe; magnitude still forwards to the base. */
String Km.describe(Km value) => %"${value.value} km";

protocol Meters(Km);

/* Cm implements nothing itself; a static adoption keeps the
   conformance local to this translation unit. */
static protocol Meters(Cm);

int main(void) {
  $scope() {
    Km trip = Km.new(3);
    Cm pencil = Cm.new(1800);

    printf("%s is %ld m\n", trip.describe(), trip.magnitude());
    printf("%s is %ld m\n", pencil.describe(), pencil.magnitude());
  }
  return 0;
}
