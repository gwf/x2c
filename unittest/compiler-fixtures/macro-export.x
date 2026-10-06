#pragma once

macro Expression $m.value() => 7;
macro Declaration $m.decl(Name $n) { int $n = 42; }
keyword mkw $m.value;
meta int m_static(int n) => n * 5;
meta int m_sum(int n) {
  int total = 0;
  foreach (int i, [1, 2, 3]) total += i * n;
  return total;
}
$(defun m_lisp () 11)
