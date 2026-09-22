/*  cmath.x -- C99 <math.h> prototypes for the compiler

    Copyright (c) 2026 Gary William Flake

    Normal declaration collection does not expand system headers, so these
    prototypes are what let a `Var` argument unbox at a `<math.h>` call.
    Every one is marked `meta`, so the compiler links it and compile-time
    code calls the native function, including through an output pointer
    such as `frexp`'s. The unit still includes `<math.h>` itself and links
    against libm where the host needs it.
*/

#pragma once

meta double acos(double);
meta double asin(double);
meta double atan(double);
meta double atan2(double, double);
meta double cos(double);
meta double sin(double);
meta double tan(double);
meta double acosh(double);
meta double asinh(double);
meta double atanh(double);
meta double cosh(double);
meta double sinh(double);
meta double tanh(double);
meta double exp(double);
meta double exp2(double);
meta double expm1(double);
meta double log(double);
meta double log10(double);
meta double log1p(double);
meta double log2(double);
meta double logb(double);
meta double frexp(double, int *);
meta double ldexp(double, int);
meta double modf(double, double *);
meta double scalbn(double, int);
meta double scalbln(double, long);
meta double cbrt(double);
meta double fabs(double);
meta double hypot(double, double);
meta double pow(double, double);
meta double sqrt(double);
meta double erf(double);
meta double erfc(double);
meta double lgamma(double);
meta double tgamma(double);
meta double ceil(double);
meta double floor(double);
meta double nearbyint(double);
meta double rint(double);
meta double round(double);
meta double trunc(double);
meta double fmod(double, double);
meta double remainder(double, double);
meta double remquo(double, double, int *);
meta double copysign(double, double);
meta double nan(const char *);
meta double nextafter(double, double);
meta double nexttoward(double, long double);
meta double fdim(double, double);
meta double fmax(double, double);
meta double fmin(double, double);
meta double fma(double, double, double);
meta int ilogb(double);
meta long lrint(double);
meta long lround(double);
meta long long llrint(double);
meta long long llround(double);

meta float acosf(float);
meta float asinf(float);
meta float atanf(float);
meta float atan2f(float, float);
meta float cosf(float);
meta float sinf(float);
meta float tanf(float);
meta float acoshf(float);
meta float asinhf(float);
meta float atanhf(float);
meta float coshf(float);
meta float sinhf(float);
meta float tanhf(float);
meta float expf(float);
meta float exp2f(float);
meta float expm1f(float);
meta float logf(float);
meta float log10f(float);
meta float log1pf(float);
meta float log2f(float);
meta float logbf(float);
meta float frexpf(float, int *);
meta float ldexpf(float, int);
meta float modff(float, float *);
meta float scalbnf(float, int);
meta float scalblnf(float, long);
meta float cbrtf(float);
meta float fabsf(float);
meta float hypotf(float, float);
meta float powf(float, float);
meta float sqrtf(float);
meta float erff(float);
meta float erfcf(float);
meta float lgammaf(float);
meta float tgammaf(float);
meta float ceilf(float);
meta float floorf(float);
meta float nearbyintf(float);
meta float rintf(float);
meta float roundf(float);
meta float truncf(float);
meta float fmodf(float, float);
meta float remainderf(float, float);
meta float remquof(float, float, int *);
meta float copysignf(float, float);
meta float nanf(const char *);
meta float nextafterf(float, float);
meta float nexttowardf(float, long double);
meta float fdimf(float, float);
meta float fmaxf(float, float);
meta float fminf(float, float);
meta float fmaf(float, float, float);
meta int ilogbf(float);
meta long lrintf(float);
meta long lroundf(float);
meta long long llrintf(float);
meta long long llroundf(float);
