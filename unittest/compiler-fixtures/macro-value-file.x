#include "x2c.x"
#include "meta.x"

#include "macro-value-file-defs.x"

/* A Macro value spells its defining file relative to the home, so the
   generated C is the same from every checkout. */
int main(void) {
  Macro imported = $sum;
  Macro anonymous = macro Expression(Expr $value) => $value + $value;
  printf("%s\n", imported.assoc(<file>).str());
  printf("%s\n", anonymous.assoc(<file>).str());
  return 0;
}
