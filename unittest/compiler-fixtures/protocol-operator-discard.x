#include "x2c.x"

/* A handle type whose operator temporaries are discarded as soon as the
   consuming operator has used them. */
typedef struct Cell {
  double value;
  double *storage;
  int discarded;
} *Cell;

static int live, discards;

protocol Arith(T) {
  T T.add(T, T);
  T T.sub(T, T);
  T T.mul(T, T);
  T T.neg(T);
  int T.truth(T);
  void T.discard(T);
}

Cell Cell.new(double value) {
  Cell cell = xcalloc(1, sizeof(struct Cell));
  cell.value = value;
  cell.storage = xmalloc(sizeof(double));
  *cell.storage = value;
  live++;
  return cell;
}

Cell double.cell(double value) => Cell.new(value);

Cell Cell.add(Cell a, Cell b) => Cell.new(a.value + b.value);

Cell Cell.sub(Cell a, Cell b) => Cell.new(a.value - b.value);

Cell Cell.mul(Cell a, Cell b) => Cell.new(a.value * b.value);

Cell Cell.neg(Cell a) => Cell.new(-a.value);

int Cell.truth(Cell a) => a.value != 0;

Cell Cell.twice(Cell a) => Cell.new(a.value * 2.0);

Cell Cell.choose(Cell temporary, Cell existing) => existing;

Cell Cell.identity(Cell value) => value;

typedef struct View { Cell value; } View;

View Cell.view(Cell value) => (View) { value };

static double consumed;

void Cell.consume(Cell a) { consumed += a.value; }

void Cell.discard(Cell a) {
  if (a.discarded) return;
  a.discarded = 1;
  xfree(a.storage);
  a.storage = NULL;
  live--;
  discards++;
}

protocol Arith(Cell);

int main(void) {
  Cell a = Cell.new(2.0), b = Cell.new(3.0), c = Cell.new(4.0);
  Cell chain = a * b + c;            // discards the product
  Cell both = (a * b) * (b * c);     // discards two products
  Cell negated = -(a + b);           // discards the sum
  Cell scaled = 2.0 * a - 1.0;       // discards two converted doubles
  Cell named = a * b;                // a named result is kept
  Cell kept = named + c;
  Cell called = (a * b).twice();     // an ordinary method may borrow its input
  Cell passed = c.add(a * b);        // and a temporary argument
  (a * c).consume();                 // a void method discards too
  printf("%g %g %g %g %g %g %g %g live %d discards %d\n",
         chain.value, both.value, negated.value, scaled.value, kept.value,
         called.value, passed.value, consumed, live, discards);
  Cell borrowed = (a * b).choose(c) + a;
  printf("borrowed %g named-discarded %d\n", borrowed.value, c.discarded);
  int before = discards;
  Cell deep = (a * b + c) * a;
  printf("deep %g discards %d\n", deep.value, discards - before);
  Cell alias = (a * b).identity();
  View view = (a * b).view();
  printf("alias %g view %g\n", alias.storage ? *alias.storage : -1.0,
         view.value.storage ? *view.value.storage : -1.0);
  Cell zero = Cell.new(0), acc = a;
  before = discards;
  acc += b * c;
  printf("update %g discards %d\n", acc.value, discards - before);
  before = discards;
  acc -= b + c;
  printf("subtract %g discards %d\n", acc.value, discards - before);
  before = discards;
  acc += b;
  printf("named update %g discards %d\n", acc.value, discards - before);
  before = discards;
  if (a + b) printf("if discards %d\n", discards - before);
  before = discards;
  int inverted = !(a + b);
  printf("not %d discards %d\n", inverted, discards - before);
  before = discards;
  int chosen = (a + b) ? 1 : 0;
  printf("conditional %d discards %d\n", chosen, discards - before);
  before = discards;
  while (a * zero) {}
  for (; a * zero;) {}
  do {} while (a * zero);
  printf("loops discards %d\n", discards - before);
  before = discards;
  int both_truth = (a + b) && (a * b);
  printf("and %d discards %d\n", both_truth, discards - before);
  before = discards;
  int one_truth = (a + b) || (a * b);
  printf("or %d discards %d\n", one_truth, discards - before);
  before = discards;
  int skipped = zero && (a * b);
  printf("skipped %d discards %d\n", skipped, discards - before);
  return 0;
}
