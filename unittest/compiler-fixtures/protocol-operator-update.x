#include "x2c.x"
#include <stdio.h>

typedef struct Bag {
  int slot[4];
} *Bag;

static int evals = 0;

Var Bag.var(Bag value) {
  return Var.new(<bag>, value);
}

Bag Var.bag(Var value) {
  return (Bag) value.pointer();
}

Var Bag.getindex(Bag bag, Var key) {
  return bag.slot[key.integer()];
}

Var Bag.setindex(Bag bag, Var key, Var value) {
  bag.slot[key.integer()] = value.integer();
  return value;
}

Var Bag.updateindex(Bag bag, Var key, Symbol op, Var rhs) {
  (void) op;
  int index = key.integer();
  bag.slot[index] = bag.slot[index] + rhs.integer();
  return bag.slot[index];
}

Var Bag.postfixindex(Bag bag, Var key, Symbol op) {
  int index = key.integer(), before = bag.slot[index];
  bag.slot[index] += op == <++> ? 1 : -1;
  return before;
}

protocol Var(Bag);

static Bag pick(Bag bag) {
  evals++;
  return bag;
}

int main(void) {
  x2c_register_type(%"bag");
  Bag bag = Scope.malloc(sizeof(struct Bag));
  bag.slot[1] = 2;
  pick(bag)[1] = 2;
  pick(bag)[1] += 10;
  Var before = pick(bag)[1]++;
  printf("%ld %ld %d\n", before.integer(), bag[1].integer(), evals);
  return 0;
}
