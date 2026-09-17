/*  bindings.x -- five ways x2c names a value: a delegate field, a Self
    result, a reference parameter, destructuring assignment, and `with`.
*/

typedef struct Reading {
  int celsius;
  int humidity;
} Reading;

int Reading.comfort(Reading reading) =>
  reading.celsius * 2 - reading.humidity / 10;

/* A delegate field answers a dotted call the outer type does not define,
   so a Station reads like the Reading it carries. */
typedef struct Station {
  delegate Reading latest;
  String name;
} Station;

/* Self promises the receiver's own typedef, so a Trail stays a Trail
   instead of decaying to the List underneath it. */
typedef List Trail;

Self Trail.record(Self trail, Var sample) => cons(sample, trail);

/* A reference parameter aliases the caller's object: the body reads and
   writes it as an ordinary int, and the call site writes no `&`. */
static void widen(int &low, int &high) {
  low -= 1;
  high += 1;
}

int main(void) {
  Station station = { { 21, 40 }, "north ridge" };
  printf("%s comfort %d\n", station.name, station.comfort());

  Trail trail = %(18 19);
  trail = trail.record(20).record(21);
  printf("trail %s of %d\n", trail.repr(), trail.len());

  int low = 12, high = 27;
  widen(low, high);
  printf("range %d..%d\n", low, high);

  /* Destructuring assignment returns its source, so one List feeds two
     views without another call or copy. */
  Var morning, evening;
  List samples = (morning, evening) = %(16 23);
  printf("morning %s evening %s from %s\n",
         morning.repr(), evening.repr(), samples.repr());

  /* `with` gives an expression a short lexical name; each use is a copy of
     the expression, not a hidden temporary. */
  with station.latest as reading {
    reading.celsius += 2;
    reading.humidity -= 5;
  }
  printf("adjusted %d %d comfort %d\n",
         station.latest.celsius, station.latest.humidity, station.comfort());
  return 0;
}
