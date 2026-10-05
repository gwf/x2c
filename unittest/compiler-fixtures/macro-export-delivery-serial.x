// An included file's exported import reaches the includer whole after a
// serial translation of that file, which the includer then replays. A
// run-time call to its meta function links the includer's own weak copy.
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
