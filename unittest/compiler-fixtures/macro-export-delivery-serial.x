// Public compile-time definitions reach consumers through includes.
#include "macro-export-lib.x"

$m.decl(declared);
int expression = $m.value();
int aliased = mkw();
int summed = $m_sum(2);
int scaled = $m_static(3);
int from_xmacro = $(m_lisp);
int from_xlisp = $(h_lisp);
int runtime_sum(void) => m_sum(2);

int main(void) {
  printf("%d %d\n", summed, runtime_sum());
  return 0;
}
