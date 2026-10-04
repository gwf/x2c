#include "x2c.x"
#include "meta.x"
#include <math.h>

/* NaN and the infinities cross the meta helper as results, quoted values,
   and typed quoted values, in double and float. */

meta static double wide(int which) {
  return which == 0 ? NAN : which == 1 ? INFINITY : -INFINITY;
}
meta static float narrow(int which) => (float) wide(which);
meta static List wide_code(int which) {
  double value = wide(which);
  return $!( $value );
}
meta static List wide_typed(int which) {
  double value = wide(which);
  return $!double{ $value };
}
meta static List narrow_code(int which) {
  float value = narrow(which);
  return $!( $value );
}
meta static List narrow_typed(int which) {
  float value = narrow(which);
  return $!float{ $value };
}

#define SHOW(label, x) \
  printf("%s %s %d %d %d\n", label, \
    _Generic((x), float: "float", double: "double", default: "other"), \
    isnan(x) != 0, isinf(x) != 0, signbit(x) != 0)

int main(void) {
  SHOW("direct", $wide(0));
  SHOW("direct", $wide(1));
  SHOW("direct", $wide(2));
  SHOW("direct", $narrow(0));
  SHOW("direct", $narrow(1));
  SHOW("direct", $narrow(2));
  SHOW("quoted", $wide_code(0));
  SHOW("quoted", $wide_code(1));
  SHOW("quoted", $wide_code(2));
  SHOW("quoted", $narrow_code(0));
  SHOW("quoted", $narrow_code(1));
  SHOW("quoted", $narrow_code(2));
  SHOW("typed", $wide_typed(0));
  SHOW("typed", $wide_typed(1));
  SHOW("typed", $wide_typed(2));
  SHOW("typed", $narrow_typed(0));
  SHOW("typed", $narrow_typed(1));
  SHOW("typed", $narrow_typed(2));
  return 0;
}
