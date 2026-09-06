/*  uv-152.h -- pinned native libuv header */

#ifndef X2C_UV_152_H
#define X2C_UV_152_H

#include <uv.h>

#if UV_VERSION_MAJOR != 1 || UV_VERSION_MINOR != 52 || \
    UV_VERSION_PATCH != 1
#error The x2c libuv client requires libuv 1.52.1.
#endif

#endif
