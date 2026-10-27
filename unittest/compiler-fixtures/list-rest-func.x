#include "x2c.x"

typedef List Type;
typedef List (*RestPointer)(int, List @);

static List collect(int prefix, List @items) => cons(prefix, items);
static int count(List @items) => items.len();
static int change(int &value, List @items) {
  value += items.len();
  return value;
}
static int effects;
static int next(void) => ++effects;
static List splice(void) { effects++; return %(8 9); }

int main(void) {
  Func f = collect, zero = count, reference = change;
  List nested = %(2 3), empty = NULL;
  Type type = %(int);
  List result = f(1, nested, type, @empty, 4, @nested, 5);
  printf("nested %d\n", result == %(1 (2 3) (int) 4 2 3 5));
  printf("zero %d %d\n", zero().int(), zero(1, 2, 3).int());
  printf("empty %d\n", f(7) == %(7));
  RestPointer pointer = collect;
  Func indirect = pointer;
  printf("pointer %d\n", indirect(6, @nested) == %(6 2 3));
  int value = 10;
  int changed = reference(value, 1, 2);
  printf("reference %d %d\n", changed, value);
  result = f(0, next(), @(splice()), next());
  printf("order %d %d\n", result == %(0 1 8 9 3), effects);
  Func lambda = %!(int prefix, List @items) => prefix + items.len();
  int captured = 20;
  Func closure = %!(List @items) => captured + items.len();
  printf("lambda %d %d\n", lambda(5, 1, 2).int(), closure(1, 2, 3).int());
  int caught = 0;
  try f(); catch %(bad-arity *): caught++;
  try f(@nested); catch %(bad-types *): caught++;
  printf("errors %d\n", caught);
  return 0;
}
