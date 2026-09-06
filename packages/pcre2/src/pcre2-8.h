/*  pcre2-8.h -- pinned native PCRE2-8 header */

#ifndef X2C_PCRE2_8_H
#define X2C_PCRE2_8_H

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#if PCRE2_MAJOR != 10 || PCRE2_MINOR != 48
#error The x2c PCRE2 client requires PCRE2 10.48.
#endif

#endif
