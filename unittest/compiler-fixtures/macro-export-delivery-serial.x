// An included file's exported import reaches the includer whole after a
// serial translation of that file, which the includer then replays.
#include "macro-export-lib.x"

$m.decl(declared);
int expression = $m.value();
int aliased = mkw();
int summed = $m_sum(2);
int scaled = $m_static(3);
int from_xmacro = $(m_lisp);
int from_xlisp = $(h_lisp);
