#include "x2c.x"

protocol Marker(T) {
  int T.mark(T);
}

typedef int Marked;

macro Unit $bad.representation() => {
  protocol Marker(Marked) as int;
}
