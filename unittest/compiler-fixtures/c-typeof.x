#include "x2c.x"
#include <stdio.h>

// `typeof` names a type by its operand. An operand x2c types names that
// type, a type operand names itself, and an operand only C can type, such
// as a system header's macro, stays for C. `typeof_unqual` drops the
// qualifiers of the type it names.
int main(void) {
  String name = "x2c";
  typeof(name) copy = name;
  __typeof__(long) wide = 1L << 40;
  __typeof__(EOF) end = EOF;
  const int fixed = 3;
  typeof_unqual(fixed) changed = fixed;
  changed += 1;
  printf("%d %ld %d %d\n", (int) copy.len(), wide, end, changed);
  return 0;
}
