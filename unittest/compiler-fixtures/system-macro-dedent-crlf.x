#include "system-macros.x"
#include <stdio.h>

macro Expression $crlf_block() => $dedent(%"
  first
  second
  ");

int main(void) {
  String folded = $dedent(%"
  first
  second
  ");
  String templated = $crlf_block();
  String escaped = $dedent("\r\n  first\r\n  second\r\n  ");
  String written = "\r\n  first\r\n  second\r\n  ";
  String runtime = written.dedent();
  if (folded != "first\nsecond\n" || templated != folded ||
      escaped != runtime || runtime != "first\r\nsecond\r\n") return 1;
  puts("dedent CRLF semantics");
  return 0;
}
