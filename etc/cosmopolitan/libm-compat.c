/*  libm-compat.c -- C99 math functions missing from Cosmopolitan 4.0.2

    The pinned SDK declares these functions but its libcosmo.a does not
    define them. The seed links them through the compile-time native targets
    of lib/cmath.x. long is 64 bits on every APE target, so the lround
    family gives the long long results exactly.
*/
#include <math.h>

__attribute__((weak)) float erfcf(float x) { return erfc(x); }

__attribute__((weak)) long long llround(double x) { return lround(x); }

__attribute__((weak)) long long llroundf(float x) { return lroundf(x); }
