#include "x2c.x"

typedef struct Pair { String first; String second; } Pair;

meta static List canonical_of(List yes, List no) {
  return %(expr (int) (initval
    ((expr (int) (literal (int) "1")) () (int) ${yes})
    (() () (int) ${no})));
}

meta static List chain_of(List value) {
  return %(expr () (composite (commas
    (indexinit (expr (int) (literal (int) "0"))
      (dotinit ("second") ${value})))));
}

macro Expression $canonical(Expr $yes, Expr $no) => $canonical_of($yes, $no);
macro Expression $chain(Expr $value) => $chain_of($value);

macro Expression $retain(Expr $value) => $value;

int main(void) {
  Pair values[1] = $retain($chain("kept"));
  printf("%d %d\n", $retain($canonical(3, 4)), values[0].second.len());
  return 0;
}
