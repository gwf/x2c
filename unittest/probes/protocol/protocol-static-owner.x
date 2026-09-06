#include "x2c.x"

typedef struct StaticMeters {
  double value;
} *StaticMeters;

typedef struct StaticFeet {
  double value;
} *StaticFeet;

protocol StaticMeters(T) {
  double T.magnitude(T);
}

static StaticMeters StaticFeet.staticmeters(StaticFeet value) {
  StaticMeters result = Scope.malloc(sizeof(struct StaticMeters));
  result.value = value.value / 2.0;
  return result;
}

static StaticFeet StaticMeters.staticfeet(StaticMeters value) {
  StaticFeet result = Scope.malloc(sizeof(struct StaticFeet));
  result.value = value.value * 2.0;
  return result;
}

double StaticMeters.magnitude(StaticMeters value) {
  return value.value;
}

protocol StaticMeters(StaticFeet);

typedef struct StaticItems {
  List values;
} *StaticItems;
typedef StaticItems StaticItemsChild;

Iter StaticItems.iter(StaticItems values, Iter dest) {
  return values.values.iter(dest);
}

static protocol Iter(StaticItems);

double static_owner_reading(StaticFeet value) {
  return value.magnitude();
}

int static_owner_total(StaticItemsChild values) {
  int total = 0;
  foreach(int value, values) total += value;
  return total;
}
