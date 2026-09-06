#include "protocol-basedefault-owner.x"

/* Consumer unit: reaches Feet.magnitude through cache/snapshot replay of
   the owner's conformance. Two distinct function bodies dot-call the
   base-default member; both must resolve to the owner-emitted generated
   binding, proving cross-unit method lookup consults the conformance
   table rather than a phantom binding defined during this unit's own
   classification. */

static double consumer_first_reading(Feet value) {
  return value.magnitude();
}

static double consumer_second_reading(Feet value) {
  return value.magnitude();
}

int main(void) {
  Feet feet = Scope.malloc(sizeof(struct Feet));
  feet.value = 3.0;
  printf("%.1f %.1f %.1f %.1f\n",
         owner_first_reading(feet), owner_second_reading(feet),
         consumer_first_reading(feet), consumer_second_reading(feet));
  return 0;
}
