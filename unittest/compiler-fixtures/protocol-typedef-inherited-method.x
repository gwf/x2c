#include "x2c.x"

typedef List Domain;
typedef Domain DomainLeaf;
typedef List Tail;

protocol Tail(T) {
  T T.cdr(T);
}
protocol Tail(Domain);
protocol Equality(T) {
  int T.equal(T, T);
}
protocol Equality(Domain);

int main(void) {
  DomainLeaf values = %(1 2 3);
  Domain same = %(1 2 3);
  Domain tail = values.cdr();
  int total = 0;
  foreach(int value, values) total += value;
  int equal = values.equal(same);
  printf("%d %d %d\n", total, tail.car().int(), equal);
  return total == 6 && tail.car().int() == 2 && equal ? 0 : 1;
}
