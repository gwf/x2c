/*  termbox2-2.5.h -- pinned native termbox2 2.5 header */

#ifndef X2C_TERMBOX2_25_H
#define X2C_TERMBOX2_25_H

#ifndef TB_LIB_OPTS
#define TB_LIB_OPTS
#endif

#include <termbox2.h>

#ifndef TB_VERSION_STR
#error The x2c termbox2 client requires termbox2 2.5.0.
#endif

typedef char x2c_termbox2_version_abi[
  sizeof(TB_VERSION_STR) == sizeof("2.5.0") ? 1 : -1
];

#if TB_OPT_ATTR_W != 64
#error The x2c termbox2 client requires 64-bit attributes.
#endif

#ifndef TB_OPT_EGC
#error The x2c termbox2 client requires extended grapheme clusters.
#endif

typedef char x2c_termbox2_attr_abi[
  sizeof(uintattr_t) == sizeof(uint64_t) ? 1 : -1
];

#endif
