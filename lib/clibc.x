/*  clibc.x -- a basic set of C library prototypes for the compiler

    Copyright (c) 2026 Gary William Flake

    Like `cmath.x`, these prototypes are marked `meta`, so the compiler links
    each function and compile-time code calls the native one. The set is
    deliberately small: integer and string conversions, string comparison,
    and the C11 clock. `<ctype.h>` is absent because C libraries may define
    its functions as macros, which a redeclaration cannot follow. Anything
    else reaches compile time through a native extension.
*/

#pragma once

#include <stdlib.h>
#include <string.h>
#include <time.h>

meta int abs(int);
meta long labs(long);
meta long long llabs(long long);
meta int atoi(const char *);
meta long atol(const char *);
meta long long atoll(const char *);
meta double atof(const char *);

meta int strcmp(const char *, const char *);
meta int strncmp(const char *, const char *, unsigned long);

struct timespec;
meta int timespec_get(struct timespec *, int);
