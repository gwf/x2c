/* A complete local struct lives in native bytes during compile-time
   execution without being adopted with `meta`. */

#include "x2c.x"

struct Point { int x, y; };

$(import "meta-record-local.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $ct_struct(4), ct_struct(argc + 3));
  return 0;
}
