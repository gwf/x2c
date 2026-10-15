/* A source name that spells another file's prefix is an ordinary name;
   only names the compiler derives from a prefixed spelling keep theirs. */
#include <stdio.h>
module {
  "module-block-prefixed-name/first.x",
  "module-block-prefixed-name/second.x",
  "module-block-prefixed-name/a.x",
  "module-block-prefixed-name/a___b.x",
}
int main(void) { set_a(9); printf("%d %d %d\n", first_value(), second_value(), read_b()); return 0; }
