#include "x2c.x"
#include "meta.x"

meta static List place_before(void) {
  x2c_place(%(before-statement), $!{ ; });
  return $!int{ 0 };
}
macro Expression $misplaced() => $place_before();

int main(void) { return $misplaced(); }
