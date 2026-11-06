/*  curl-822.h -- pinned native libcurl 8.22.0 header */

#ifndef X2C_CURL_822_H
#define X2C_CURL_822_H

#include <curl/curl.h>

/* A missing header reports itself; skip the version checks. */
#if __has_include(<curl/curl.h>)

#if LIBCURL_VERSION_MAJOR != 8 || LIBCURL_VERSION_MINOR != 22 || \
    LIBCURL_VERSION_PATCH != 0
#error The x2c libcurl client requires libcurl 8.22.0.
#endif

#endif

#endif
