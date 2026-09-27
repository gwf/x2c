// A `meta` definition that matches its linked copy but calls an edited
// definition runs as written: the copy has the shipped callee frozen in.
#include "x2c.x"

meta static int _dedent_width(String line) { return 123; }
meta static int _dedent_blank(String line) =>
  _dedent_width(line) == line.len();

int main(void) {
  printf("%d %d %d\n", $_dedent_width("abc"), $_dedent_blank("   "),
         _dedent_blank("   "));
  return 0;
}
