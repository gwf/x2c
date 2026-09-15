#!/usr/bin/env -S x2c script
/* Conditional directives around top-level statements select statements in
   the script body. */

#define VERBOSE 1

#if VERBOSE
printf("verbose statement\n");
#else
printf("quiet statement\n");
#endif

#ifndef MISSING
printf("missing is undefined\n");
#endif
