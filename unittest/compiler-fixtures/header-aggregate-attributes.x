/* Collection reads an included header's aggregates past their attributes,
   including string arguments, after the keyword and after the closing
   brace, and the declarations that follow them. */

#include "header-aggregate-attributes/attributes.h"

int main(void) {
  struct Aligned aligned = { 'a' };
  printf("%c %d\n", aligned.tag, aligned_size());
  return 0;
}
