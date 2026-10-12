/* A member path may pass through '..' when the location it resolves to
   stays under the companion directory. */
#include <stdio.h>

module {
  "module-block-member-paths/sub/value.x",
  "module-block-member-paths/sub/../member.x",
}

int main(void) {
  printf("%d\n", member_total());
  return 0;
}
