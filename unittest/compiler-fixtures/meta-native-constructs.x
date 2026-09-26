/*  meta-native-constructs.x -- C constructs a `meta` function runs as C

    A bodied `meta` function is compiled by the ordinary backend and run as
    native code, so every construct its C form has runs at compile time
    with its C meaning: `goto`, a `switch` arm that falls through, a
    runtime file static, a preprocessor name, a bitfield, an enum wider
    than `int`, and a local static.
*/

#include "x2c.x"

#define LIMIT 5

static int base = 10;

struct Bits { unsigned value : 3; };

enum Wide { SMALL = 0, WIDE = 0x100000000 };
struct Holder { enum Wide wide; int tail; };

$(import "meta-native-constructs.xmacro")

int main(void) {
  printf("goto %d %d\n", $jump(0), $jump(1));
  printf("fallthrough %d %d\n", $fall(1), $fall(2));
  printf("static %d\n", $offset(5));
  printf("macro %d\n", $limit());
  printf("bitfield %d\n", $bits());
  printf("wide enum %d\n", $tail());
  printf("local static %d\n", $first());
  return 0;
}
