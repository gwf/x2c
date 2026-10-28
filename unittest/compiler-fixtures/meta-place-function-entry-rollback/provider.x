#include "x2c.x"
#include "meta.x"

meta List place_entry(List value) {
  x2c_place(%(function-entry), $!{ (void) (value is int); });
  return value;
}
