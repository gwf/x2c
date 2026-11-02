#include "x2c.x"

/* Only a consumer completes an Iter chain. A chain passed as an argument
   keeps its stages one argument short, and x2c reports the first of them
   before the C compiler sees the call. */

static int consume(Iter it) {
  int count = 0;
  Var item;
  while (it.try_next(item)) count++;
  return count;
}

int main(void) {
  List xs = %(1 2 3);
  return consume(xs.iter().map(%!(x) => x * 2));
}
