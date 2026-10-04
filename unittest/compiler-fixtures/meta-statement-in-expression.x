#include "x2c.x"
#include "meta.x"

/* A meta call inside an expression stays an expression, so a statement
   result there is rejected. */
meta static List quoted_statement(void) => $!{ puts("x"); };

int main(void) {
  int count = 0;
  count += ($quoted_statement(), 1);
  return count;
}
