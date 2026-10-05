#include "x2c.x"
#include "meta.x"

/* A data List returned to a whole statement outside an expansion stays a
   runtime value; binding it as syntax would fail. */
meta static List data(void) => %(a b c);

int main(void) {
  $data();
  return 0;
}
