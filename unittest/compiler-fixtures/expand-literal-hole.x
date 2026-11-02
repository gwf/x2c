#include "x2c.x"

/* An expand row gives a Literal hole the literal a source argument would
   be: a String row is a string literal, a number its numeral, and a Symbol
   its Symbol literal. */
int main(void) {
  expand %(("hello" 1 left) ("world" 2.5 right))
  macro Stmt(Literal $text, Literal $count, Literal $side) {
    printf("%s %s %s\n", $text, ((Var) $count).repr(), $side.str());
  }
  return 0;
}
