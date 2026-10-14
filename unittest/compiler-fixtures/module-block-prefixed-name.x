/* A source name that spells another file's prefix is an ordinary name;
   only names the compiler derives from a prefixed spelling keep theirs. */
#include <stdio.h>
module {
  "module-block-prefixed-name/first.x",
  "module-block-prefixed-name/second.x",
}
int main(void) { printf("%d %d\n", first_value(), second_value()); return 0; }
