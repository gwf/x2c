/*  string.x -- canonical byte strings and core text operations

    Copyright (c) 2025 Gary William Flake

    String owns canonical immutable byte strings. Equal nonempty contents in
    one pool chain share one pointer, the empty String is native zero, and a
    private header before the bytes holds the exact length and a cached
    content hash. A String cannot hold an embedded NUL, and every operation
    here works on bytes, without Unicode character semantics.

    A canonical String belongs to the pool that interned it or to an
    ancestor, and releasing that pool invalidates it unless it was promoted.
    A transient `String.malloc` buffer belongs to the active pool until it is
    interned or freed. Pool storage and registration causes transfer and
    never return to the constructing operation.
*/

#pragma once

#include "common.x"

/** An immutable canonical NUL-terminated byte string, or NULL for empty.
    Equal nonempty contents visible in one `String`/`List` pool chain share a
    pointer. Assignment borrows that pointer; it does not copy or extend the
    owning pool's lifetime. `String.malloc` is the mutable exception;
    its backing allocation still belongs to the active pool, and must be
    finalized with `String.intern_free` or released with `String.free`.
*/
typedef char *String;

protocol const char *(T) {
  size_t T.c_len(T)        = strlen;
  int    T.c_compare(T, T) = strcmp;
  char * T.c_find(T, int)  = strchr;
}

protocol const char *(String);

#include <stdlib.h>
#include <ctype.h>
#include <assert.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>

#include "var/var.x"
#include "list/list.x"
#include "array.x"
#include "buffer.x"
#include "exception.x"
#include "func.x"
#include "symbol.x"
#include "pool/pool.x"

/* Internal constructor for borrowed spans already known to contain no NUL.
   Callers establish the length; canonicalization uses the active pool. */
String x2c_string_from_bytes(const char *bytes, int length);

module {
  "storage.x",
  "search.x",
  "editing.x",
  "building.x",
  "splitting.x",
  "mapping.x",
  "adapters.x",
}
