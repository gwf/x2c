#include "system-macros.x"

/* A method is a type-qualified function. A reference receiver updates the
   original record. delegate forwards unresolved methods through a field. */
typedef struct Counter { int value; } Counter;
static void Counter.add(Counter &c, int amount) => c.value += amount;
static int Counter.read(Counter c) => c.value;
typedef struct Meter { delegate Counter counter; } Meter;
typedef List Trail;
static Self Trail.record(Self trail, Var item) => cons(item, trail);

int main(void) {
  Counter counter = {2};
  counter.add(3);
  Counter copy = counter;
  copy.add(1);
  Meter meter = {counter};
  Trail trail = %(2);
  trail = trail.record(3).record(4);
  puts($dedent(%"
    Original counter: $(counter.read())
    Copied counter: $(copy.read())
    Delegated counter: $(meter.read())
    Trail after recording: $(trail.repr())"));
  return 0;
}
