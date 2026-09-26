/* Value selectors and rendering share native results for present values.
   Absent selectors follow the existing meta lookup convention. */

#include "x2c.x"
$(import "meta-value-aliases.xmacro")

int main(void) {
  printf("%d %d\n", $(selectors 0), selectors(0));
  printf("%d %d\n", $(inspect 0), inspect(0));
  printf("%s\n%s\n", $(rendered "a"), rendered("a"));
  printf("%d\n", $(absent_selectors 0));
  return 0;
}
