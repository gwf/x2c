// A `meta` definition that matches its linked copy but calls an edited
// definition runs as written: the copy has the shipped callee frozen in.
#include "x2c.x"

meta static Symbol _tag_kind(List row) => <integer>;
meta static int _tag_floating(List row) => _tag_kind(row) == <floating>;

int main(void) {
  printf("%s %d %d\n", $_tag_kind(%(unused unused floating)).str(),
         $_tag_floating(%(unused unused floating)),
         _tag_floating(%(unused unused floating)));
  return 0;
}
