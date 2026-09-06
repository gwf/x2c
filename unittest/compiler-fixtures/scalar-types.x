#include "x2c.x"

#include <limits.h>

typedef unsigned long ulong_alias;
typedef unsigned int uint_alias;

static ulong_alias add_alias(ulong_alias left, uint_alias right) {
  return left + right;
}

static long double add_long_double(double long left, int right) {
  return left + right;
}

static unsigned long long add_unsigned(long unsigned long left, long right) {
  return left + right;
}

static int add_promoted(unsigned char left, signed char right) {
  return left + right;
}

static ulong_alias unbox_alias(Var value) {
  return value;
}

int main(void) {
  Var vlong = 11L;
  Var vhex = 0xffffffff;
  Var vdecimal = 4294967295;
  Var vull = 18446744073709551615ULL;
  Var vfloat = 1.25f;
  Var vlong_double = 1.5L;
  Var valias = (ulong_alias) 17;
  ulong_alias alias_value = unbox_alias(valias);

  printf("%d %d %d %d %d %d %d\n",
         vlong is <long> && vlong.long() == 11L,
         vhex is <u32> && vhex.uint() == UINT_MAX,
         vdecimal is <long> && vdecimal.long() == 4294967295L,
         vull is <ullong> &&
           vull.ulong_long() == 18446744073709551615ULL,
         vfloat is <f32> && vfloat.floating() == 1.25,
         vlong_double is <ldouble> &&
           vlong_double.long_double() == 1.5L,
         add_alias(alias_value, 2U) == 19UL &&
           add_long_double(2.5L, 2) == 4.5L &&
           add_unsigned(ULLONG_MAX - 2, 1L) == ULLONG_MAX - 1 &&
           add_promoted(250, -2) == 248);
  return 0;
}
