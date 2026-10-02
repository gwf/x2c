// The unchanged linked caller must use the edited static dependency.
#include "x2c.x"

meta static Symbol edited_kind(List row) { (void) row; return <integer>; }

meta static Symbol (*_tag_kind)(List row) = edited_kind;

meta static int _tag_floating(List row) => _tag_kind(row) == <floating>;

int main(void) {
  printf("%d %d\n", $_tag_floating(%(unused unused floating)),
         _tag_floating(%(unused unused floating)));
  return 0;
}
