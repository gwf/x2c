#include "x2c.x"

/* A handle type whose operator temporaries are discarded as soon as the
   consuming operator has used them. */
typedef struct Cell {
  double value;
  int discarded;
} *Cell;

static int live, discards;

protocol Arith(T) {
  T T.add(T, T);
  T T.sub(T, T);
  T T.mul(T, T);
  T T.neg(T);
  void T.discard(T);
}

Cell Cell.new(double value) {
  Cell cell = Scope.calloc(1, sizeof(struct Cell));
  cell.value = value;
  live++;
  return cell;
}

Cell double.cell(double value) => Cell.new(value);

Cell Cell.add(Cell a, Cell b) => Cell.new(a.value + b.value);

Cell Cell.sub(Cell a, Cell b) => Cell.new(a.value - b.value);

Cell Cell.mul(Cell a, Cell b) => Cell.new(a.value * b.value);

Cell Cell.neg(Cell a) => Cell.new(-a.value);

Cell Cell.twice(Cell a) => Cell.new(a.value * 2.0);

static double consumed;

void Cell.consume(Cell a) { consumed += a.value; }

void Cell.discard(Cell a) {
  if (a.discarded) return;
  a.discarded = 1;
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
  Cell called = (a * b).twice();     // a method discards its receiver
  Cell passed = c.add(a * b);        // and a temporary argument
  (a * c).consume();                 // a void method discards too
  printf("%g %g %g %g %g %g %g %g live %d discards %d\n",
         chain.value, both.value, negated.value, scaled.value, kept.value,
         called.value, passed.value, consumed, live, discards);
  return 0;
}
