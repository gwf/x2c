// A static function belongs to the file that defines it, so calling one
// from an including unit is reported here rather than left to the linker.
#include "unit-static-call/source.x"

int main(void) {
  return shared_value(1) + above_boundary(2);
}
