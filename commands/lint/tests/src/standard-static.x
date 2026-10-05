/* Bound references and conservative syntax mentions retain static code. */
static int _unused_signal(int n) => n + 1;
static int _direct_signal(int n) => n + 2;
static int _value_signal(int n) => n + 3;
static int _quoted_signal(int n) => n + 4;
static int _ident_signal(int n) => n + 5;
static int _cross_signal(int n) => n + 6;

typedef struct Counter { int count; } Counter;
static int Counter.step(Counter &c) => ++c.count;

protocol Metric(T) {
  int T.amount(T item);
}
typedef int Reading;
static int Reading.amount(Reading n) => n;
protocol Metric(Reading);

$(def held_function (quote _quoted_signal))
macro Expression $fixture.reference() => $(x2c.ident "_ident_signal");

int static_refs(void) {
  int (*operation)(int) = _value_signal;
  Counter counter = {0};
  return operation(_direct_signal(1)) + counter.step();
}
