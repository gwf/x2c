#include "x2c.x"

typedef struct Reading {
  int value;
} *Reading;

typedef struct Gauge {
  Reading reading;
} *Gauge;

protocol Reading(T) {
  int T.value(T);
}

Reading Gauge.reading(Gauge gauge) {
  return gauge.reading;
}

int Reading.value(Reading reading) {
  return reading.value;
}

protocol Reading(Gauge);

int main(void) {
  Reading reading = Scope.malloc(sizeof(struct Reading));
  reading.value = 42;
  Gauge gauge = Scope.malloc(sizeof(struct Gauge));
  gauge.reading = reading;
  printf("%d\n", gauge.value());
  return gauge.value() == 42 ? 0 : 1;
}
