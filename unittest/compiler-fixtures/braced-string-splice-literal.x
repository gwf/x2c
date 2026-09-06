#include "x2c.x"

/* Inside %"" only `$` begins interpolation. The braced splice spelling has
   no string meaning: `@{...}` stays literal segment text rather than
   splicing or diagnosing. List-context behavior is covered by the braced
   splice tests. */

int main(void) {
  List values = %(a b);
  String braced = %"head @{values} foot";
  printf("%s\n", braced.str());
  return braced == %"head @{values} foot" && values.len() == 2 ? 0 : 1;
}
