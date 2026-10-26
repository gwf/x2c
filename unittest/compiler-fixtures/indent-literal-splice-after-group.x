#pragma indent
#include "x2c.x"

/* In the indentation syntax, `@rest` after a group inside a literal is an
   element, so the line still ends its statement. */
int main(void):
  int x = 1
  List rest = %(2 3)
  List xs = %($(x + 0) @rest $x)
  printf("%s\n", xs.repr())
  return 0
