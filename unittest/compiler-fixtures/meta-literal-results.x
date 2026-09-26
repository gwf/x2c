#include "x2c.x"
#include <math.h>

meta double half(double x) { return x / 2.0; }
meta float fraction(void) { return 0.125f; }
meta unsigned char byte_value(int x) { return (unsigned char)x; }
meta unsigned long long widest(void) {
  return 18446744073709551615ULL;
}
meta long long negative(void) { return -9223372036854775807LL - 1LL; }
meta String label(void) { return %"ready"; }
meta List items(void) { return %(1 "two" three); }
meta int minimum_int(void) { return -2147483647 - 1; }
meta int meta_length(List xs) { return xs.len(); }

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
