/*  alias-module-nested.x -- a nested member's static alias of one name

    The outer member's `static` alias stays its own while an inner member
    it splices declares a `static` alias of the same name, and it applies
    again when the outer member's text resumes.
*/

#include <stdio.h>

module {
  "alias-module-nested/outer.x",
}

int main(void) {
  printf("%d %d %d\n", before_value(), inner_value(), after_value());
  return 0;
}
