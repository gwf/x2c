#ifndef X2C_BLIS_21_H
#define X2C_BLIS_21_H

#include <blis/blis.h>

#if BLIS_VERSION_MAJOR != 2 || BLIS_VERSION_MINOR != 1
#error "x2c BLIS client requires BLIS 2.1"
#endif

#ifndef BLIS_DISABLE_BLAS
#error "x2c BLIS client requires BLAS compatibility disabled"
#endif

#ifndef BLIS_DISABLE_CBLAS
#error "x2c BLIS client requires CBLAS compatibility disabled"
#endif

#endif
