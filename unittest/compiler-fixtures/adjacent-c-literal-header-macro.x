#include "x2c.x"
#include "adjacent-c-literal-header-macro-values.h"

// A header's string macro stands before a literal as it stands after one.
int main(void) {
  String before = MARK " first";
  puts(before);
  puts("second " MARK);
  puts(MARK " and " MARK);
  return 0;
}
