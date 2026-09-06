#include "x2c.x"

typedef List Domain;

protocol Mappable(T) {
  T T.map(T, Func);
}

protocol Mappable(Domain);

int main(void) {
  return 0;
}
