/* In an expression, `receiver.name(arguments)` invokes the Expression
   macro `$T.name` of the receiver's named type, which shadows the method
   `T.name`. Inside its own expansion, `receiver.name(...)` is the method,
   so the macro can wrap it. Another method of the type is unaffected. */

#include <stdio.h>

typedef struct Counter { int base; } Counter;

static int Counter.add(Counter counter, int n) => counter.base + n;
static int Counter.twice(Counter counter) => counter.base * 2;

macro Expression $Counter.add(Expr $counter, Expr $n) =>
  $counter.add($n) * 100;

static int reads;

static Counter counter_of(Counter counter) {
  reads++;
  return counter;
}

int main(void) {
  Counter counter = { 1 };
  int sum = counter.add(2) + counter_of(counter).add(3);
  printf("%d %d %d\n", sum, reads, counter.twice());
  return 0;
}
