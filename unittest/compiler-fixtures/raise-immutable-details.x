#include "x2c.x"

typedef enum DetailKind {
  DETAIL_ONE,
  DETAIL_TWO
} DetailKind;

static void allowed(
  int small, long wide, DetailKind kind, Symbol symbol, Atom atom, String text,
  List list, Var dynamic) {
  raise %(invariant
          (small $small)
          (wide $wide)
          (kind $kind)
          (symbol $symbol)
          (atom $atom)
          (text $text)
          (list $list)
          (nested ($text ($wide $symbol)))
          (dynamic $dynamic));
}

int main(void) {
  return 0;
}
