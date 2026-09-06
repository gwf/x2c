/*  cmath.x -- C99 <math.h> prototypes for the compiler

    Copyright (c) 2026 Gary William Flake

    x2c never reads system headers, so these prototypes are what let a `Var`
    argument unbox at a `<math.h>` call. The unit still includes `<math.h>`
    itself and links against libm where the host needs it.
*/

#pragma once

double acos(double);
double asin(double);
double atan(double);
double atan2(double, double);
double cos(double);
double sin(double);
double tan(double);
double acosh(double);
double asinh(double);
double atanh(double);
double cosh(double);
double sinh(double);
double tanh(double);
double exp(double);
double exp2(double);
double expm1(double);
double log(double);
double log10(double);
double log1p(double);
double log2(double);
double logb(double);
double frexp(double, int *);
double ldexp(double, int);
double modf(double, double *);
double scalbn(double, int);
double scalbln(double, long);
double cbrt(double);
double fabs(double);
double hypot(double, double);
double pow(double, double);
double sqrt(double);
double erf(double);
double erfc(double);
double lgamma(double);
double tgamma(double);
double ceil(double);
double floor(double);
double nearbyint(double);
double rint(double);
double round(double);
double trunc(double);
double fmod(double, double);
double remainder(double, double);
double remquo(double, double, int *);
double copysign(double, double);
double nan(const char *);
double nextafter(double, double);
double nexttoward(double, long double);
double fdim(double, double);
double fmax(double, double);
double fmin(double, double);
double fma(double, double, double);
int ilogb(double);
long lrint(double);
long lround(double);
long long llrint(double);
long long llround(double);
