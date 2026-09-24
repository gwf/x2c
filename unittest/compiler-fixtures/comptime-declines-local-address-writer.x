/*  comptime-declines-local-address-writer.x -- a meta function returns the
    Buffer that a container writer handed back

    `write_str` and `write_repr` return their Buffer argument, so returning
    a parameter Buffer through them is allowed, and returning a local
    Buffer's address through them is the escape.
*/

#include "x2c.x"

meta static Buffer array_text(Array a, Buffer buffer) =>
  a.write_repr(a.write_str(buffer));

meta static Buffer map_text(Map m, Buffer buffer) =>
  m.write_repr(m.write_str(buffer));

meta static Buffer array_leak(Array a) {
  struct Buffer buffer = {0};
  return a.write_str(&buffer);
}

meta static Buffer map_leak(Map m) {
  struct Buffer buffer = {0};
  return m.write_repr(&buffer);
}

int main(void) { return 0; }
