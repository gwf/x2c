// The caller matches its linked copy before the edited callee is parsed.
#include "x2c.x"

meta static int _tag_floating(List row) => _tag_kind(row) == <floating>;
meta static Symbol _tag_kind(List row) => <integer>;

int main(void) {
  printf("%s %d %d\n", $_tag_kind(%(unused unused floating)).str(),
         $_tag_floating(%(unused unused floating)),
         _tag_floating(%(unused unused floating)));
  return 0;
}
