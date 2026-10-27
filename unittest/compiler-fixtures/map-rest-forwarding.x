#include "x2c.x"
#include <assert.h>

typedef struct Measure { long value; } *Measure;
typedef struct Reading { Measure measure; } *Reading;

protocol Measure(T) {
  long T.total(T, Map @values);
}

Measure Reading.measure(Reading value) => value.measure;

long Measure.total(Measure value, Map @values) {
  long result = value.value;
  foreach (Var item in values) result += item.integer();
  return result;
}

protocol Measure(Reading);

int main(void) {
  struct Measure measure = { 10 };
  struct Reading reading = { &measure };
  Reading value = &reading;
  Map more = {b: 2, c: 3};
  assert(value.total() == 10);
  assert(value.total(a: 1, @more, d: 4) == 20);
  puts("map rest forwarding ok");
  return 0;
}
