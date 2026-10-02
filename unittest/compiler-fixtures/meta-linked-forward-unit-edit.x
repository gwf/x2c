// Collection defers this local Unit macro until its helpers are installed.
#include "x2c.x"

meta static int _tag_floating(List row) => _tag_kind(row) == <floating>;

macro Unit $kind_reader(Name $reader) {
  static int $reader(void) {
    return $_tag_floating(%(unused unused floating));
  }
}

$kind_reader(read_kind);

meta static Symbol _tag_kind(List row) => <integer>;

int main(void) {
  printf("%d %d\n", read_kind(), _tag_floating(%(unused unused floating)));
  return 0;
}
