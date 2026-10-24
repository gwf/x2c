/*  alias-module.x -- aliases in a module unit

    A member's alias stays visible to the members and entry text after it,
    as a macro does. A `static` alias stays in its member, so another member
    may declare a static of the same name.
*/

#include <stdio.h>

module {
  "alias-module/first.x",
  "alias-module/second.x",
}

int main(void) {
  printf("%d %d %d\n", scaled, first_value(), second_value());
  return 0;
}
