#include "x2c.x"

/* An `expand` row whose generator gives Map entries makes a bare brace a
   Map literal, as an entry row does, in its first row as in a later one. */
int main(void) {
  Map first = {
    expand %(("a" 1) ("b" 2))
    macro Entry(Literal $key, Expr $value) { $key: $value }
  };
  Map later = {
    "z": 0,
    expand %(("a" 1) ("b" 2))
    macro Entry(Literal $key, Expr $value) { $key: $value }
  };
  printf("%s %s\n", first.repr(), later.repr());
  return 0;
}
