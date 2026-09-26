/* Native math functions and a scalar class are usable at compile time.
   Ordinary native-reaching calls remain in generated C. */

#include "x2c.x"

class MetaCount int;

$(import "meta-native-functions.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%.1f %.1f %d\n",
    $(native_total 0.0), native_total(argc - 1), $(class_value 6));
  return 0;
}
