// A forward static dependency must prevent reuse of the linked caller.
#include "x2c.x"

meta static Symbol edited_kind(List row) { (void) row; return <integer>; }

meta static int _tag_floating(List row) => _tag_kind(row) == <floating>;

meta static Symbol (*_tag_kind)(List row) = edited_kind;

int main(void) {
  printf("%d %d\n", $_tag_floating(%(unused unused floating)),
         _tag_floating(%(unused unused floating)));
  return 0;
}
