#include "x2c.x"

typedef struct Pair { String first; String second; } Pair;

macro Expression $canonical(Expr $yes, Expr $no) => (
  $(list 'expr '(int) (list 'initval
    (list '(expr (int) (literal (int) "1")) '() '(int) $yes)
    (list '() '() '(int) $no)))
)

macro Expression $chain(Expr $value) => (
  $(list 'expr '() (list 'composite (list 'commas
    (list 'indexinit '(expr (int) (literal (int) "0"))
      (list 'dotinit '("second") $value)))))
)

macro Expression $retain(Expr $value) => ($value)

int main(void) {
  Pair values[1] = $retain($chain("kept"));
  printf("%d %d\n", $retain($canonical(3, 4)), values[0].second.len());
  return 0;
}
