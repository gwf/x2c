#include "x2c.x"
#include <math.h>

$(import "meta-literal-results.xmacro")

int main(void) {
  printf("%.1f %.3f %u %llu %lld %s\n", $(half 9.0), $(fraction),
    (unsigned)$(byte_value 257), $(widest), $(negative), label().str());
  printf("%d %d %d\n", _Generic($(fraction), float: 1, default: 0),
    _Generic($(widest), unsigned long long: 1, default: 0),
    meta_length(items()));
  printf("%d %d\n", _Generic($(minimum_int), int: 1, default: 0),
    _Generic(minimum_int(), int: 1, default: 0));
  return 0;
}
