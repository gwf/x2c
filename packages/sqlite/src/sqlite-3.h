/* sqlite-3.h -- complete pinned SQLite 3.53.4 C interface. */

#pragma once

#include <sqlite3.h>

#if SQLITE_VERSION_NUMBER != 3053004
#error "the x2c sqlite client requires SQLite 3.53.4"
#endif

#if defined(SQLITE_THREADSAFE) && SQLITE_THREADSAFE != 1
#error "the x2c sqlite client requires the serialized SQLite profile"
#endif
