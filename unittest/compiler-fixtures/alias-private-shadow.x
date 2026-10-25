/*  alias-private-shadow.x -- body aliases shadow a file-private alias */

#include <stdio.h>

module { "alias-private-shadow/member.x", }

int main(void) {
  printf("%d %d %d %d %d\n", first_value(), inner_value(), last_value(),
         outer_value(), field_count());
  return 0;
}
