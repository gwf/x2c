$(import "system-macros.xmacro")
#include <stdio.h>

int main(void) {
  String folded = $dedent(%"
  first
  second
  ");
  String templated = $dedent(%"
  first
  second
  ");
  String written = "\r\n  first\r\n  second\r\n  ";
  String runtime = written.dedent();
  if (folded != runtime || templated != runtime ||
      folded != "first\r\nsecond\r\n") return 1;
  puts("dedent CRLF parity");
  return 0;
}
