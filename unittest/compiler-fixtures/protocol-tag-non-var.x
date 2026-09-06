#include "x2c.x"

protocol Marker(T) {
  int T.mark(T);
}

typedef int Marked;
protocol Marker(Marked) tag <list>;
