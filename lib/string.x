/*  string.x -- canonical byte strings and core text operations

    Copyright (c) 2025 Gary William Flake

    A `String` is an immutable, interned, NUL-terminated byte sequence. Equal
    nonempty `String`s visible in one pool chain share one canonical pointer,
    and the empty `String` is native zero. A private header before the bytes
    holds the exact length and a cached content hash. A `String` cannot hold
    an embedded NUL, and every operation here works on bytes, without Unicode
    character semantics.

    A canonical `String` belongs to the pool that interned it or to an
    ancestor, and releasing that pool invalidates it unless it was promoted.
    A transient `String.malloc` buffer belongs to the active pool until
    `String.intern_free` makes it canonical or `String.free` releases it.
    Constructing a nonempty `String` may raise `<alloc-fail>`, `<size-limit>`,
    or `<invariant>` through pool storage and registration; these causes
    transfer and never return to the operation.
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

/*  String adopts the native const char * protocol beside its declaration. */
protocol const char *(String);

#pragma private

#include <stdlib.h>
#include <ctype.h>
#include <assert.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>

#include "var.x"
#include "list.x"
#include "array.x"
#include "buffer.x"
#include "exception.x"
#include "func.x"
#include "symbol.x"
#include "pool.x"

// representation

/* `length` includes the trailing NUL. A zero hash marks an unfinished
   String.malloc buffer; canonical nonempty Strings have their content hash
   installed before entering a pool table. */
typedef struct StringHeader {
  int length;
  unsigned hash;
} *StringHeader;

/* Canonical String payloads are custom-object-safe: Scope allocations are
   max-aligned and the payload begins eight bytes after the base. */
_Static_assert(
  sizeof(struct StringHeader) == 8,
  "the String header is 8 bytes, so payloads stay aligned");

/* Results up to this many bytes are built and probed on the stack. */
#define STRING_STACK_BYTES 256

/* A short String and its header on the stack, so probing the pool chain
   for it allocates nothing. */
typedef union StringQuery {
  unsigned long align;
  char bytes[sizeof(struct StringHeader) + STRING_STACK_BYTES + 1];
} StringQuery;

static inline StringHeader _header(String str) =>
  (StringHeader) ((char *) str - sizeof(struct StringHeader));

static unsigned _hash_n(const char *str, int length) =>
  x2c_hash_bytes(0, str, (size_t) length);

/** Returns the byte length of `str`, excluding the terminating NUL.
    Constant time: the length is cached in the `String`'s private header.
    Lengths count bytes, so a multibyte UTF-8 sequence counts once per byte.
    On a transient `String.malloc` buffer this reports the writable byte
    count.

    The empty `String` is the null pointer, whose length is 0.
*/
int String.len(String str) {
  if (!str) return 0;
  return _header(str).length - 1;
}

/** Returns the content hash of `str`, or zero for the empty `String`.
    Canonical `String`s use the cached hash; transient buffers are hashed from
    their current NUL-terminated contents.
*/
meta native unsigned String.hash(String str) {
  if (!str || !*str) return 0;
  StringHeader header = _header(str);
  return header.hash ? header.hash : _hash_n(str, strlen(str));
}

/** Reports whether `x` and `y` contain the same bytes.
    Interning already makes `x == y` a content test for two canonical
    `String`s, so use this when one side may be a transient
    `String.malloc` buffer or when null has to compare cleanly. Two nulls
    are equal, since the null pointer is the empty `String`, and a null
    equals no non-empty `String`.
*/
int String.equal(String x, String y) {
  if ((void *) x == (void *) y) return 1;
  if (!x || !y) return 0;
  return strcmp(x, y) == 0;
}

/** Compares `x` and `y` bytewise, returning negative, zero, or positive.
    The ordering is C's `strcmp` on the raw bytes, so it is neither
    locale-aware nor Unicode collation, and only the sign of the result is
    meaningful. The empty `String`, being the null pointer, sorts before
    every non-empty `String`, and two empty `String`s compare equal.
*/
meta native int String.compare(String x, String y) {
  if ((void *) x == (void *) y) return 0;
  if (!x) return -1;
  if (!y) return 1;
  int result = strcmp(x, y);
  return (result > 0) - (result < 0);
}

// canonical construction

/** Returns the canonical `String` holding the bytes of the C string `str`.
    The input is borrowed and copied, so `str` may be a stack buffer and
    mutating it afterwards does not disturb the result. Equal nonempty content
    visible in the active pool chain yields the same pointer, which is why
    `==` on canonical `String`s from that chain is a content comparison. A
    detached or sibling pool may hold a distinct equal pointer. Empty input
    canonicalizes to the null pointer, the empty `String`'s only
    representation.
    Raises: `<alloc-fail>` when canonical storage cannot be allocated. A null,
    empty, or oversized input returns NULL, which is indistinguishable from the
    empty `String`, without raising.
*/
String String.new(const char *str) {
  if (!str || !*str) return NULL;
  size_t length = strlen(str);
  if (length > INT_MAX - 1) return NULL;
  return _from_bytes(str, (int) length);
}

/** Returns the canonical `String` holding at most `len` bytes of `str`.
    Copying stops at `len` bytes or at the first NUL, whichever comes
    first, because a `String` cannot carry embedded NUL bytes:
    `String.new_len("ab\0cd", 5)` is the two-byte `String` `ab`. `str` need
    not be NUL-terminated, so it may be bounded C input or a window into a
    larger buffer.
    Raises: `<alloc-fail>` when canonical storage cannot be allocated. A null
    `str`, nonpositive `len`, or leading NUL returns NULL, the empty `String`,
    without raising.
*/
String String.new_len(const char *str, int len) {
  if (!str || len <= 0) return NULL;
  size_t length = strnlen(str, (size_t) len);
  if (length == 0) return NULL;
  return _from_bytes(str, (int) length);
}

/** Returns the canonical `String` for at most `length` borrowed bytes in
    `pool`.
    The active pool does not change. Copying stops at the first NUL. An
    existing equal `String` in `pool` or an ancestor is returned with that
    owner's lifetime; otherwise the new value is owned by `pool`. A null
    argument, nonpositive length, or empty input returns NULL.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while interning.
*/
String String.new_in(Pool pool, const char *bytes, int length) {
  if (!pool || !bytes || length <= 0) return NULL;
  size_t bounded = strnlen(bytes, (size_t) length);
  if (!bounded || bounded > INT_MAX - 1) return NULL;
  return _from_bytes_in(pool, bytes, (int) bounded);
}

/** Returns the canonical `String` for the borrowed bytes of `string`.
    This is `String.new` under another name. The bytes are copied into
    canonical storage and the caller keeps ownership of whatever buffer it
    passed in, so a stack array or a C library return value is a fine
    argument. It is not the finalizer for a `String.malloc` buffer:
    handing one here interns a second copy and leaves the buffer for the
    caller to free. Use `String.intern_free` for an owned buffer.
    Raises: `<alloc-fail>` when canonical storage cannot be allocated. `Null`
    or empty input returns NULL, the empty `String`, without raising.
*/
meta native Self String.intern(Self string) => string.new();

static String _from_bytes(const char *bytes, int length) =>
  _from_bytes_in(Pool.current(), bytes, length);

/* A short `String` probes the whole ancestor chain from a stack copy before
   anything is allocated, and a miss is installed in `pool`. A long one is
   stored first, and Pool.intern releases that candidate on a hit. */
static String _from_bytes_in(Pool pool, const char *bytes, int length) {
  if (!pool || !bytes || length <= 0) return NULL;
  unsigned hash = _hash_n(bytes, length);
  if (length <= STRING_STACK_BYTES) {
    Var existing = _lookup_bytes(pool, bytes, length, hash);
    if (existing is not void) return existing;
  }
  size_t total = sizeof(struct StringHeader) + (size_t) length + 1;
  StringHeader header = pool.malloc(total);
  String string = _store(header, bytes, length, hash);
  if (length > STRING_STACK_BYTES) return pool.intern(string, header);
  pool.insert(string);
  return string;
}

/* Probes the pool chain from a stack copy of at most STRING_STACK_BYTES
   bytes. */
static Var _lookup_bytes(
  Pool pool, const char *bytes, int length, unsigned hash) {
  StringQuery query;
  return pool.lookup(_store((StringHeader) query.bytes, bytes, length, hash));
}

/* Fills `header` and the `length` bytes after it, with their NUL, and
   returns those bytes as a String. */
static inline String _store(
  StringHeader header, const char *bytes, int length, unsigned hash) {
  header.length = length + 1;
  header.hash = hash;
  String string = (String) ((char *) header + sizeof(struct StringHeader));
  memcpy(string, bytes, length);
  char *out = string;
  out[length] = '\0';
  return string;
}

// transient buffers

/** Allocates a transient mutable buffer of `len` bytes, not a `String`.
    The byte count includes room for the terminating NUL, so `len - 1`
    bytes are writable and `String.len` on a fresh buffer reports
    `len - 1`. The buffer is not interned and has no cached hash, so `==`
    against a canonical `String` is meaningless until it is finalized. Fill
    it with native indexing, then call `String.intern_free` to canonicalize
    and release it, or `String.free` to discard it. The backing allocation
    belongs to the active `String`/`List` pool and is invalidated when that
    pool is released, even though the caller controls finalization.

    ```x2c
    String buf = String.malloc(6);
    printf("%d writable bytes\n", buf.len());
    ~String.free(buf);
    ```
    Raises: `<alloc-fail>` when storage cannot be allocated. A nonpositive or
    oversized `len` returns NULL without raising.
*/
String String.malloc(int len) {
  if (len <= 0) return NULL;
  if ((size_t) len > SIZE_MAX - sizeof(struct StringHeader)) return NULL;
  size_t total_len = sizeof(struct StringHeader) + (size_t) len;
  Pool pool = Pool.current();
  StringHeader header = pool.malloc(total_len);
  header.length = len;
  header.hash = 0;
  return (String) ((char *) header + sizeof(struct StringHeader));
}

/** Finalizes an owned `String.malloc` buffer into a canonical `String`.
    This takes ownership. The length and hash are computed from the
    buffer's NUL-terminated contents, then the buffer either becomes the
    canonical `String` for that content or, when an equal canonical `String`
    already exists, is released in favor of the existing one. Either way
    the argument must not be used again; keep the return value. Passing an
    already canonical `String` visible in the active pool chain is a harmless
    no-op that returns it unchanged. The argument and its storage must be
    visible in that chain; a canonical `String` from a detached or sibling pool
    is not valid here because installing its pointer would outlive its storage.

    ```x2c
    ~String buf = String.malloc(6);
    ~char *bytes = buf;
    ~for (int i = 0; i < 5; i++) bytes[i] = 'a' + i;
    String canonical = buf.intern_free();
    printf("%s %d\n", canonical, canonical == "abcde");
    ```
    Raises: `<alloc-fail>` when the canonical value cannot be registered. A
    null argument returns NULL, and a buffer empty at its first byte is
    released and reported as NULL, the empty `String`, without raising.
*/
Self String.intern_free(Self string) {
  if (string == NULL) return NULL;
  if (!*string) {
    _free_unchecked(string);
    return NULL;
  }
  return _intern_owned(string);
}

/* Finalization consumes a mutable Pool allocation: install the header,
   then keep the buffer or the canonical hit. */
static String _finish(String string, int length) {
  if (length <= 0) {
    _free_unchecked(string);
    return NULL;
  }
  assert(memchr(string, '\0', length) == NULL);
  char *out = string;
  out[length] = '\0';
  StringHeader header = _header(string);
  header.length = length + 1;
  header.hash = _hash_n(string, length);
  return _intern_owned(string);
}

/* Installs a nonempty buffer that the active pool chain owns without
   copying it, or releases it for an equal canonical `String`. Installing a
   detached or sibling-owned pointer would leave a table entry dangling when
   that other pool is released. */
static String _intern_owned(String string) {
  StringHeader header = _header(string);
  if (!header.hash) {
    int length = strlen(string);
    header.length = length + 1;
    header.hash = _hash_n(string, length);
  }
  Pool pool = Pool.current();
  Var existing = pool.lookup(string);
  if (existing is void) {
    pool.insert(string);
    return string;
  }
  String found = existing;
  if (found !== string) _free_unchecked(string);
  return found;
}

/** Releases a transient `String.malloc` buffer early.
    The pointer is first looked up in the intern table, including the
    enclosing pools, and the call does nothing if it is the canonical `String`
    visible from the active pool. Only a transient buffer allocated in the
    active pool chain is released; a canonical pointer from a detached or
    unrelated pool is not a valid argument.

    A null argument is ignored.
*/
meta native void String.free(String str) {
  if (str == NULL) return;
  if (_header(str).hash) {
    Var existing = Pool.current().lookup(str);
    if (existing is not void && existing.string() === str) return;
  }
  _free_unchecked(str);
}

/* Only Pool-backed transient or losing-candidate storage may enter here;
   callers establish that the pointer is not a live canonical table entry. */
static void _free_unchecked(String str) {
  if (str != NULL) Pool.current().free(_header(str));
}

// pool ownership

/** Moves `str` from the active pool to its parent and returns the same
    pointer. Empty, transient, and ancestor-owned `String`s are returned
    unchanged.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while recording
    the promotion.
*/
Self String.promote(Self str) {
  if (!str || !*str) return str;
  Pool.current().promote(str, _header(str));
  return str;
}

/** Proves `str` safe beyond every active canonical `String` pool.
    Returns 1 when `str` is empty, already permanent, or can be promoted to
    the outermost pool. Returns 0 when no active pool owns it. Promotion
    proceeds one pool at a time; if a later step fails, the earlier promotions
    remain.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while recording a
    promotion.
*/
int String.try_own(String str) {
  if (!str || !*str) return 1;
  return Pool.current().own(str, _header(str));
}

/** Asks whether `str` already outlives every canonical `String` pool.
    Returns 1 when `str` is empty or the outermost pool owns it, and 0 for a
    transient buffer or a `String` a nested pool can still reclaim. Unlike
    `String.try_own` it neither promotes nor allocates, so a caller may ask
    about a `String` it does not own.
*/
int String.is_permanent(String str) {
  if (!str || !*str) return 1;
  return Pool.is_permanent(str);
}

/* True when `str` is the canonical `String` visible from the active pool,
   which an operation that changes nothing may return. */
static int _is_active_canonical(String str) =>
  Pool.current().lookup(str) === str;

// search

/** Returns the index of the first occurrence of `sub` in `str`, or -1.
    The search compares bytes, so an index may land inside a multibyte
    sequence. An empty `sub` matches at index 0. Use `String.find_within` to
    bound the search to a range, or `String.rfind` to scan from the end.
*/
meta native int String.find(String str, String sub) =>
  str.find_within(sub, 0, -1);

/** Returns the first index of `sub` within `str[start:end]`, or -1.
    The returned index is absolute and counts from the start of `str`.
    Negative `start` and `end` count from the end of `str`, and both are then
    clamped to the `String`.

    An `end` of -1 is the sentinel for "to the end of `str`", not "one byte
    before the end". There is therefore no negative `end` that excludes only
    the last byte; pass a nonnegative `end` for that. An empty `sub` matches at
    the normalized `start`.

    ```x2c
    ~String text = "abcabc";
    printf("%d %d %d\n", text.find_within("c", 0, -1),
           text.find_within("c", 0, 2), text.find_within("a", -3, -1));
    ```
*/
meta native int String.find_within(
  String str, String sub, int start, int end) {
  int n = str.len(), m = sub.len();
  if (start < 0) start += n;
  if (end == -1) end = n;
  else if (end < 0) end += n;
  start = _clamp(start, n);
  end = _clamp(end, n);
  if (start + m > end) return -1;
  if (m == 0) return start;
  if (!str) return -1;
  const char *p = _find_bytes(str + start, end - start, sub, m);
  if (!p) return -1;
  return (int) (p - str);
}

static int _clamp(int index, int n) {
  if (index < 0) return 0;
  return index > n ? n : index;
}

static const char *_find_bytes(
  const char *haystack, int haystack_len, const char *needle, int needle_len) {
  if (needle_len == 0) return haystack;
  if (!haystack || haystack_len < needle_len) return NULL;
  for (int i = 0; i <= haystack_len - needle_len; i++)
    if ((unsigned char) haystack[i] == (unsigned char) needle[0] &&
        memcmp(haystack + i, needle, needle_len) == 0)
      return haystack + i;
  return NULL;
}

/** Returns the index of the last occurrence of `sub` in `str`, or -1.
    Scanning runs backwards from the end, and the returned index still
    measures from the start of `str`. An empty `sub` reports the length of
    `str`, matching after the last byte and mirroring the forward search
    reporting 0.
*/
meta native int String.rfind(String str, String sub) {
  int n = str.len(), m = sub.len();
  if (m == 0) return n;
  if (!str || m > n) return -1;
  for (int i = n - m; i >= 0; i--) if (memcmp(str + i, sub, m) == 0) return i;
  return -1;
}

/** Returns each non-overlapping starting index at which `sub` occurs.
    The search begins at `start` and uses the same normalized exclusive `end`
    as `String.find_within`. `Null` or empty `str` or `sub` returns `nil`. The
    result is a canonical `List` whose cells follow their owning pools.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
meta native List String.find_all(String str, String sub, int start, int end) {
  if (!str || !sub) return %();
  Array results = [], int n = sub.len(), pos = start;
  for (;;) {
    pos = str.find_within(sub, pos, end);
    if (pos < 0) break;
    results.push(pos);
    pos += n;
  }
  return results.list_free();
}

/** Returns the non-overlapping count of `sub` in `str`.
    A null or empty `str` or `sub` returns zero.
*/
meta native int String.count(String str, String sub) {
  if (!str || !sub) return 0;
  return _count_matches(str, sub, -1);
}

/* Counts non-overlapping occurrences of `sub` in `str`, left to right, up to
   `limit` of them; a negative `limit` counts every match. */
static int _count_matches(String str, String sub, int limit) {
  int str_len = str.len(), sub_len = sub.len(), count = 0, pos = 0;
  while (pos <= str_len - sub_len && (limit < 0 || count < limit)) {
    const char *found = _find_bytes(str + pos, str_len - pos, sub, sub_len);
    if (!found) break;
    count++;
    pos = (int) (found - str) + sub_len;
  }
  return count;
}

/** Reports whether the bytes of `sub` occur anywhere in `str`.
    An empty `sub` is contained in every `String`, including the empty one,
    so a truth test on user-supplied text should check for emptiness
    separately if that matters.
*/
meta native int String.contains(String str, String sub) {
  if (!sub) return 1;
  if (!str) return 0;
  if (sub.len() == 1) return strchr(str, sub[0]) != NULL;
  return str.find(sub) != -1;
}

/** Reports whether `str` starts with `prefix`.
    An empty `prefix` is a prefix of every `String`. `String.remove_prefix`
    performs the same test and returns the remainder, so there is rarely a
    reason to run both.
*/
meta native int String.startswith(String str, String prefix) {
  int str_len = str.len(), prefix_len = prefix.len();
  if (prefix_len == 0) return 1;
  return str && prefix_len <= str_len && memcmp(str, prefix, prefix_len) == 0;
}

/** Reports whether `str` ends with `suffix`.
    An empty `suffix` is a suffix of every `String`. The comparison is
    bytewise, so this is a safe test for a file extension but not for a
    case-insensitive one; lower both sides first.
*/
meta native int String.endswith(String str, String suffix) {
  int str_len = str.len(), suffix_len = suffix.len();
  if (suffix_len == 0) return 1;
  return str && suffix_len <= str_len &&
         memcmp(str + str_len - suffix_len, suffix, suffix_len) == 0;
}

// replacement

/** Returns `str` with every occurrence of `old` replaced by `replacement`.
    Scanning runs left to right and matches do not overlap: each one
    resumes after the text it consumed, so replacing `aa` in `aaaa` performs
    two replacements, not three. Replaced text is never rescanned, so a
    `replacement` that contains `old` does not loop. An empty `replacement`
    deletes the matches.

    When there is nothing to replace, `str` itself is returned, so the
    result may be the same pointer as the input.
    Raises: `<alloc-fail>` when result storage cannot be allocated. An empty
    or null `old` returns `str`, and an oversized result returns NULL, without
    raising.
*/
meta native String String.replace(
  String str, String old, String replacement) =>
  str.replace_n(old, replacement, -1);

/** Replaces at most `max_replacements` non-overlapping occurrences of `old`.
    Scanning proceeds left to right and does not rescan replacement text. A
    negative limit replaces all matches; zero, null or empty `old`, null input,
    or no match returns `str` unchanged. `Null` `replacement` deletes matches.
    An oversized result returns NULL.
    Raises: `<alloc-fail>` while constructing a changed result.
*/
meta native String String.replace_n(
  String str, String old, String replacement, int max_replacements) {
  if (!str || !old || !*old || max_replacements == 0) return str;
  if (old == replacement && _is_active_canonical(str)) return str;
  int str_len = str.len(), old_len = old.len();
  int replacement_len = replacement.len();
  int count = _count_matches(str, old, max_replacements);
  if (count == 0) return str;
  int length = _replaced_length(str_len, count, old_len, replacement_len);
  if (length < 0) return NULL;
  String string = String.malloc(length + 1);
  char *dst = string, int copied = 0, replaced = 0;
  while (copied <= str_len - old_len && replaced < count) {
    const char *found = _find_bytes(
      str + copied, str_len - copied, old, old_len);
    int prefix_len = (int) (found - (str + copied));
    memcpy(dst, str + copied, prefix_len);
    dst += prefix_len;
    if (replacement_len) {
      memcpy(dst, replacement, replacement_len);
      dst += replacement_len;
    }
    copied = (int) (found - str) + old_len;
    replaced++;
  }
  memcpy(dst, str + copied, str_len - copied);
  return _finish(string, length);
}

/* The length after `count` replacements of `old_len` bytes by `new_len`
   bytes, or -1 when the result cannot fit a String. */
static int _replaced_length(int length, int count, int old_len, int new_len) {
  size_t total = (size_t) length;
  if (new_len >= old_len) {
    size_t growth = (size_t) (new_len - old_len);
    if (growth && (size_t) count > ((size_t) (INT_MAX - 1) - total) / growth)
      return -1;
    total += (size_t) count * growth;
  }
  else total -= (size_t) count * (old_len - new_len);
  return total > INT_MAX - 1 ? -1 : (int) total;
}

// indexing and slicing

/** Returns the byte at `index` in `str` as an int, or -1 if out of range.
    This is what `str[index]` lowers to on a canonical `String`, so indexing
    yields an int byte value. A negative `index` counts from the end, so -1
    is the last byte.

    The byte is unsigned, so the result is 0 through 255 on every platform and
    -1 means out of range and nothing else. An `index` at or beyond the length
    is out of range.
*/
int String.getindex(String str, int index) {
  index = x2c_normalize_index(index, str.len());
  if (index < 0) return -1;
  return (unsigned char) *(str + index);
}

/** Returns the canonical `String` `s[start:stop:step]`.
    This is what slice syntax lowers to. `stop` is exclusive, negative
    `start` and `stop` count from the end, and a negative `step` walks
    backwards, so `s[::-1]` reverses. Indices are byte positions, so a
    slice can split a multibyte sequence. A full unit-step slice may return
    `s`; other nonempty slices return their canonical `String`.
    Raises: `<alloc-fail>` while constructing a nonempty result. An empty
    range, a range that runs the wrong way for its `step`, or a `step` of zero
    also returns NULL, the empty `String`, without raising.
*/
meta native String String.getslice(String s, int start, int stop, int step) {
  if (!s || step == 0) return NULL;
  int n = s.len(), len = x2c_normalize_slice(&start, &stop, step, n);
  if (len <= 0) return NULL;
  if (step == 1 && start == 0 && len == n && _is_active_canonical(s)) return s;
  if (step == 1) return _from_bytes(s + start, len);
  String string = String.malloc(len + 1);
  char *out = string, const char *src = s;
  for (int i = 0, idx = start; i < len; i++, idx += step) out[i] = src[idx];
  return _finish(string, len);
}

/** Returns a canonical copy of `str` with the byte at `index` set.
    Canonical `String`s are immutable, so `str` is not modified. When the byte
    already has `value`, this may return `str`; otherwise a new `String` is
    built and interned. Native assignment `str[index] = value` writes through
    shared canonical storage and belongs only on a transient `String.malloc`
    buffer. A negative `index` counts from the end.

    ```x2c
    String word = "hello";
    String capital = word.withindex(0, 'H');
    printf("%s %s\n", word, capital);
    ```
    Raises: `<bad-arg>` when `value` is NUL, which a `String` cannot contain,
    or `<alloc-fail>` while constructing the result. An out-of-range `index`
    returns `str` unchanged.
*/
meta native String String.withindex(String str, int index, char value) {
  if (!str || !*str) return str;
  if (value == '\0')
    raise %(bad-arg (owner "String.withindex") (index $index));
  int n = str.len();
  if (index < 0) index += n;
  if (index < 0 || index >= n) return str;
  if (str[index] == value && _is_active_canonical(str)) return str;
  String string = String.malloc(n + 1);
  memcpy(string, str, n);
  char *out = string;
  out[index] = value;
  return _finish(string, n);
}

// building

/** Returns `str` followed by `other`.
    This implements the `add` row of `protocol Var(String)`, so it is what
    `+` on two `String`s lowers to, and because the result is interned, `==`
    on a newly built result is a content comparison. Either operand may be
    the empty `String`, in which case the other pointer is returned unchanged
    with its existing ownership and canonical or transient state.

    Every concatenation interns its result, so building text by repeated
    concatenation in a loop allocates and hashes at every step. Use
    `Buffer` for that, or collect the pieces and call `String.join` once.
    Raises: `<size-limit>` when the result cannot fit the `String`
    representation. Allocation failures propagate from the owning allocator.
*/
String String.add(String str, String other) {
  if (!other) return str;
  if (!str) return other;
  int left_len = str.len(), right_len = other.len();
  size_t length = (size_t) left_len + (size_t) right_len;
  if (length > INT_MAX - 1) raise %(size-limit (operation "String.add"));
  if (length <= STRING_STACK_BYTES) {
    char bytes[STRING_STACK_BYTES];
    memcpy(bytes, str, left_len);
    memcpy(bytes + left_len, other, right_len);
    return _from_bytes(bytes, (int) length);
  }
  String string = String.malloc((int) length + 1);
  memcpy(string, str, left_len);
  memcpy(string + left_len, other, right_len);
  return _finish(string, (int) length);
}

/** Returns a canonical `String` containing `count` copies of `str`.
    `Null` or empty input, a nonpositive count, or an oversized result returns
    NULL. A count of one returns `str` when it is already visible in the active
    pool; a transient buffer is copied and interned instead.
    Raises: `<alloc-fail>` while constructing a nonempty result.
*/
meta native String String.repeat(String str, int count) {
  if (!str || !*str || count <= 0) return NULL;
  if (count == 1 && _is_active_canonical(str)) return str;
  int n = str.len();
  if ((size_t) n > (size_t) (INT_MAX - 1) / (size_t) count) return NULL;
  size_t length = (size_t) n * (size_t) count;
  String string = String.malloc((int) length + 1), char *dst = string;
  for (int i = 0; i < count; i++) {
    memcpy(dst, str, n);
    dst += n;
  }
  return _finish(string, (int) length);
}

/** Returns the canonical `String` containing `count` copies of `fill`.
    Raises: `<bad-arg>` when `fill` is NUL, `<size-limit>` when `count` is
    `INT_MAX`, because the allocation includes one trailing NUL byte, or
    `<alloc-fail>` when canonical storage cannot be allocated. A nonpositive
    `count` returns NULL without raising.
*/
meta native String String.new_fill(char fill, int count) {
  if (count <= 0) return NULL;
  if (fill == '\0') raise %(bad-arg (owner "String.new_fill"));
  if (count == INT_MAX)
    raise %(size-limit (owner "String.new_fill") (count $count));
  String string = String.malloc(count + 1);
  memset(string, fill, count);
  return _finish(string, count);
}

/** Joins `strings` into one canonical `String` with `sep` between elements.
    The receiver is the separator, not the sequence, so this reads
    `sep.join(parts)`. A null `sep` joins with nothing between elements.
    Empty elements contribute no bytes but still count as positions, so
    joining a split result with the same separator reproduces the original
    text, adjacent separators included. `List` elements that are not `String`s
    convert to the empty `String`.
    Raises: `<alloc-fail>` when result storage cannot be allocated. A null or
    empty `List`, or an oversized result, also returns NULL, the empty
    `String`, without raising.
*/
meta native String String.join(String sep, List strings) {
  if (!strings) return NULL;
  int n = strings.len();
  if (n == 0) return NULL;
  int sep_len = sep ? sep.len() : 0;
  int total = _join_length(strings, n, sep_len);
  if (total < 0) return NULL;
  if (total <= STRING_STACK_BYTES) {
    char bytes[STRING_STACK_BYTES];
    _join_into(bytes, strings, sep, sep_len);
    return _from_bytes(bytes, total);
  }
  String string = String.malloc(total + 1);
  _join_into(string, strings, sep, sep_len);
  return _finish(string, total);
}

/* The joined length of the `n` elements, or -1 when it cannot fit a
   String. */
static int _join_length(List strings, int n, int sep_len) {
  if (sep_len && (size_t) (n - 1) > (size_t) (INT_MAX - 1) / (size_t) sep_len)
    return -1;
  size_t total = (size_t) (n - 1) * (size_t) sep_len;
  foreach (String str, strings) {
    int length = str.len();
    if ((size_t) length > (size_t) (INT_MAX - 1) - total) return -1;
    total += (size_t) length;
  }
  return (int) total;
}

static void _join_into(char *out, List strings, String sep, int sep_len) {
  for (List p = strings; p; p = p.cdr()) {
    String str = p.car();
    if (str) {
      int length = str.len();
      memcpy(out, str, length);
      out += length;
    }
    if (p.cdr() && sep) {
      memcpy(out, sep, sep_len);
      out += sep_len;
    }
  }
}

/** Pads the left side of `str` to the requested width.
    Raises: `<bad-arg>` when `fill` is NUL, `<size-limit>` when `width`
    cannot be represented, or `<alloc-fail>` when result storage cannot be
    allocated.
*/
meta native String String.pad_left(String str, int width, char fill) =>
  _pad(str, width, fill, 1);

/** Pads the right side of `str` to the requested width.
    Raises: the same causes as `String.pad_left`.
*/
meta native String String.pad_right(String str, int width, char fill) =>
  _pad(str, width, fill, 0);

/** Pads both sides of `str` to the requested width.
    Raises: the same causes as `String.pad_left`.
*/
meta native String String.pad_center(String str, int width, char fill) =>
  _pad(str, width, fill, -1);

/* `side` puts the padding on the left when 1, on the right when 0, and on
   both sides when -1, with an odd byte on the right. */
static String _pad(String str, int width, char fill, int side) {
  if (fill == '\0') raise %(bad-arg (owner "String.pad"));
  int length = str.len();
  if (width <= length) return str;
  if (width == INT_MAX)
    raise %(size-limit (owner "String.pad") (width $width));
  int padding = width - length, left = side ? padding : 0;
  if (side < 0) left = padding / 2;
  int right = padding - left, String string = String.malloc(width + 1);
  memset(string, fill, left);
  if (length) memcpy(string + left, str, length);
  memset(string + left + length, fill, right);
  return _finish(string, width);
}

// trimming and splitting

/** Returns `str` with leading and trailing bytes in `negChars` removed.
    `negChars` is a NUL-terminated C string listing the bytes to remove, not
    a substring and not a pattern; order and repetition in it are irrelevant.
    Passing NULL uses the default whitespace set " \t\n\v\f\r". Trimming
    stops at each end on the first byte not in the set, and `str` itself is
    returned when nothing is trimmed.
    Raises: `<alloc-fail>` while constructing the result. A `String` made
    entirely of removable bytes trims to NULL, the empty `String`, without
    raising.
*/
String String.strip(String str, char *negChars) {
  if (!negChars) negChars = " \t\n\v\f\r";
  int start = 0, end = str.len();
  while (start < end && strchr(negChars, str[start])) start++;
  while (end > start && strchr(negChars, str[end - 1])) end--;
  if (start == 0 && end == str.len()) return str;
  return String.new_len(str + start, end - start);
}

/** Removes leading bytes found in the C string `negChars`.
    Passing NULL uses `" \t\n\v\f\r"`. The result is canonical; null input
    returns NULL and an unchanged input is returned as-is.
    Raises: `<alloc-fail>` while constructing a changed result.
*/
String String.lstrip(String str, char *negChars) {
  if (!negChars) negChars = " \t\n\v\f\r";
  int beg = 0, length = str.len();
  while (beg < length && strchr(negChars, str[beg])) beg++;
  if (beg == 0) return str;
  return String.new(str + beg);
}

/** Removes trailing bytes found in the C string `negChars`.
    Passing NULL uses `" \t\n\v\f\r"`. The result is canonical; null input
    returns NULL and an unchanged input is returned as-is.
    Raises: `<alloc-fail>` while constructing a changed result.
*/
String String.rstrip(String str, char *negChars) {
  if (!negChars) negChars = " \t\n\v\f\r";
  int len = str.len();
  while (len > 0 && strchr(negChars, str[len - 1])) len--;
  if (len == str.len()) return str;
  return String.new_len(str, len);
}

/** Removes the indentation the text was written with.
    The prefix is the run of spaces and tabs that opens the first content
    line, after one leading newline is dropped. Every following line that
    starts with that prefix loses exactly it, so indentation written past the
    prefix survives and the block renormalizes as a unit. A line that does not
    carry the prefix, including a blank one, is left alone, except that a
    final line of only spaces and tabs is removed so the closing quote's own
    indentation does not reach the result. `\r\n` is preserved because only
    the prefix after a newline is removed.
    Raises: `<alloc-fail>` while constructing a changed result. Null input
    returns NULL and text with no prefix is returned as-is.
*/
meta native String String.dedent(String str) {
  if (!str) return NULL;
  int length = str.len(), skip = _newline_width(str), width = 0;
  while (skip + width < length &&
         (str[skip + width] == ' ' || str[skip + width] == '\t'))
    width++;
  String prefix = String.new_len(str + skip, width);
  String body = String.new(str + skip + width);
  if (width) body = body.replace(%"\n$prefix", "\n");
  int end = body.len(), tail = end;
  while (tail > 0 && (body[tail - 1] == ' ' || body[tail - 1] == '\t')) tail--;
  if (tail == end || (tail > 0 && body[tail - 1] != '\n')) return body;
  return String.new_len(body, tail);
}

/* The width of the one line break that may open a dedented text. */
static int _newline_width(String str) {
  if (str.startswith("\r\n")) return 2;
  return str.startswith("\n") ? 1 : 0;
}

/** Removes `prefix` when `str` starts with it and returns a canonical
    `String`.
    A null or absent prefix returns `str` unchanged; removing the complete
    `String` returns NULL.
    Raises: `<alloc-fail>` while constructing a changed result.
*/
meta native String String.remove_prefix(String str, String prefix) {
  if (!prefix || !str.startswith(prefix)) return str;
  return String.new_len(str + prefix.len(), str.len() - prefix.len());
}

/** Removes `suffix` when `str` ends with it and returns a canonical `String`.
    A null or absent suffix returns `str` unchanged; removing the complete
    `String` returns NULL.
    Raises: `<alloc-fail>` while constructing a changed result.
*/
meta native String String.remove_suffix(String str, String suffix) {
  if (!suffix || !str.endswith(suffix)) return str;
  return String.new_len(str, str.len() - suffix.len());
}

/** Splits `str` at the first `sep` into a three-element `List`.
    The elements are the text before the separator, the separator itself,
    and the text after it. When `sep` does not occur, the result is `str`
    followed by two empty `String`s, so the shape is three elements either
    way and a caller can destructure it without testing for the separator
    first. A leading separator gives an empty first element and a missing
    separator gives two empty trailing elements, so compare the middle element
    against `sep` if you need to tell them apart. The result and any new
    substrings are canonical and follow their owning `List` and `String` pools.
    Unchanged `str` and `sep` elements are borrowed into the result, so a
    transient input must outlive the returned `List`.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
meta native List String.partition(String str, String sep) {
  String empty = NULL;
  if (!sep) return %( $str $empty $empty );
  int sep_length = sep.len(), found = str.find(sep);
  if (found < 0) return %( $str $empty $empty );
  String before = String.new_len(str, found);
  String after = String.new_len(
    str + found + sep_length, str.len() - found - sep_length);
  return %( $before $sep $after );
}

/** Splits `str` around its final occurrence of `sep`.
    The three elements are the text before the separator, the separator itself,
    and the text after it. When `sep` is null or absent, two empty `String`s
    precede `str`. New substrings are canonical; the result follows its owning
    `List` and `String` pools. Unchanged `str` and `sep` elements are
    borrowed into the result, so a transient input must outlive the returned
    `List`.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
meta native List String.rpartition(String str, String sep) {
  String empty = NULL;
  if (!sep) return %( $empty $empty $str );
  int sep_length = sep.len(), found = str.rfind(sep);
  if (found < 0) return %( $empty $empty $str );
  String before = String.new_len(str, found);
  String after = String.new_len(
    str + found + sep_length, str.len() - found - sep_length);
  return %( $before $sep $after );
}

// byte maps

/* Builds a same-length copy whose byte `$index` is `$mapped`, with the
   source byte offered as `$byte` so each family member gives only its own C
   case mapping. A copy that changes nothing is released and `$subject`
   itself is returned. */
macro Statement $string.remap(
  Expr $subject, Name $index, Name $byte, Expr $mapped) {
  if (!$subject || !*$subject) return $subject;
  int length = $subject.len(), changed = 0;
  String string = String.malloc(length + 1);
  char *out = string;
  const char *src = $subject;
  for (int $index = 0; $index < length; $index++) {
    int $byte = (unsigned char) src[$index];
    (out)[$index] = $mapped;
    if ((out)[$index] != src[$index]) changed = 1;
  }
  if (!changed) {
    _free_unchecked(string);
    return $subject;
  }
  return _finish(string, length);
}

/** Returns `str` with every upper-case byte lowered.
    Case mapping runs byte by byte through C's `tolower`, so it covers
    ASCII in the default locale and does not case-fold multibyte text. When
    no byte would change, `str` itself is returned after the unchanged
    temporary buffer is released.
    Raises: `<alloc-fail>` while constructing the result.
*/
meta native String String.lower(String str) {
  $string.remap(str, i, ch, tolower(ch));
}

/** Returns `str` with every lower-case byte raised.
    Like `String.lower`, mapping runs byte by byte through C's `toupper` and
    covers ASCII in the default locale. `str` itself is returned when nothing
    would change.
    Raises: `<alloc-fail>` while constructing the result.
*/
meta native String String.upper(String str) {
  $string.remap(str, i, ch, toupper(ch));
}

/** Upper-cases the first byte of `str` and lower-cases the remainder.
    Mapping is bytewise through C's `toupper` and `tolower`. `Null`, empty, and
    unchanged inputs are returned as-is.
    Raises: `<alloc-fail>` while constructing the result.
*/
meta native String String.capitalize(String str) {
  $string.remap(str, i, ch, i == 0 ? toupper(ch) : tolower(ch));
}

/* Builds a filtered copy, leaving each caller to give only its byte test. */
macro Statement $string.select(
  Expr $subject, Name $index, Expr $selected) {
  int length = $subject.len();
  String string = String.malloc(length + 1);
  int done = 0;
  defer if (!done) string.free();
  char *dst = string;
  for (int $index = 0; $index < length; $index++)
    if ($selected) *dst++ = $subject[$index];
  String result = _finish(string, (int) (dst - string));
  done = 1;
  return result;
}

/** Returns the bytes of `str` accepted by ordinary `Var` truthiness of `fn`.
    Each byte is boxed from `char` and passed by value. A null or empty `str`,
    or a null `fn`, returns `str` without invoking the callback. Otherwise `fn`
    is called once per byte from left to right and is not retained.
    Raises: whatever `Func.apply`, `fn`, or the returned `Var`'s truth
    operation raises, or `<alloc-fail>` when the result cannot be allocated.
*/
String String.filter(String str, Func fn) {
  if (!str || !fn || !*str) return str;
  $string.select(str, i, _apply(fn, str[i]));
}

static Var _apply(Func fn, char value) {
  FuncArg arguments[1] = { FuncArg.value(value) };
  return fn.apply(1, arguments);
}

/** Returns `str` with `fn` applied to every byte.
    Each byte is boxed from `char` and passed by value. Each result is
    converted to `int` and truncated to the byte that is stored, and that byte
    is what is checked, so a result such as 256 raises because its stored byte
    would be NUL.
    A null or empty `str`, or a null `fn`, returns `str` without invoking the
    callback. Otherwise `fn` is called once per byte from left to right and is
    not retained. Each result must convert to a non-NUL byte.
    Raises: whatever `Func.apply`, `fn`, or result conversion raises,
    `<bad-result>` when the converted result is zero, or `<alloc-fail>` when
    the result cannot be allocated.
*/
String String.map(String str, Func fn) {
  if (!str || !fn || !*str) return str;
  int n = str.len(), done = 0;
  String string = String.malloc(n + 1);
  defer if (!done) string.free();
  char *out = string, const char *src = str;
  for (int i = 0; i < n; i++) {
    char ch = (char) _apply(fn, src[i]);
    if (!ch) raise %(bad-result (owner "String.map") (index $i));
    out[i] = ch;
  }
  String result = _finish(string, n);
  done = 1;
  return result;
}

/** Returns a canonical `String` containing only bytes found in `chars`.
    `Null` `str` returns NULL; null `chars` returns NULL for any nonnull input.
    Raises: `<alloc-fail>` while constructing the result.
*/
meta native String String.keep(String str, String chars) {
  if (!str) return str;
  if (!chars) return NULL;
  if (!*str) return str;
  $string.select(str, i, strchr(chars, str[i]));
}

/** Returns a canonical `String` after removing bytes found in `chars`.
    `Null` or empty `str`, or null `chars`, returns `str` unchanged.
    Raises: `<alloc-fail>` while constructing a changed result.
*/
meta native String String.reject(String str, String chars) {
  if (!str || !chars || !*str) return str;
  $string.select(str, i, !strchr(chars, str[i]));
}

/** Collapses adjacent runs of each byte listed in `chars`.
    Bytes outside `chars` are preserved even when repeated. `Null` or empty
    `str`, or null `chars`, returns `str` unchanged.
    Raises: `<alloc-fail>` while constructing a changed result.
*/
meta native String String.squeeze(String str, String chars) {
  if (!str || !chars || !*str) return str;
  $string.select(
    str, i, !(i && str[i] == str[i - 1] && strchr(chars, str[i])));
}

/* formatting

   `String.printf` passes C arguments to `vsnprintf`. `String.format` parses
   a checked subset of the same syntax itself and converts each `Var` value
   to the C type its conversion names. */

/** Formats a canonical `String` from `fmt` and the trailing arguments.
    The receiver is the format `String`, so format-dependent construction reads
    `%"%-12s %.2f".printf(name, score)`. Conversions, promotion rules, and
    argument matching are C's, since the work is done by `vsnprintf`;
    canonical `String`s are NUL-terminated and satisfy `%s` directly. Prefer
    `%"$name has ${name.len()} bytes"` when interpolation already says what
    you want.
    Raises: `<alloc-fail>` when result storage cannot be allocated. An empty
    `fmt` or formatting error also returns NULL without raising. Arguments
    that do not match the conversions are undefined behavior as in C.
*/
String String.printf(String fmt, ...) {
  if (!fmt || !*fmt) return NULL;
  va_list args, measure;
  va_start(args, fmt);
  va_copy(measure, args);
  int n = vsnprintf(NULL, 0, fmt, measure);
  va_end(measure);
  if (n < 0) {
    va_end(args);
    return NULL;
  }
  if (n <= STRING_STACK_BYTES) {
    char bytes[STRING_STACK_BYTES + 1];
    int written = vsnprintf(bytes, n + 1, fmt, args);
    va_end(args);
    if (written != n) return NULL;
    return _from_bytes(bytes, n);
  }
  String string = String.malloc(n + 1);
  int written = vsnprintf(string, n + 1, fmt, args);
  va_end(args);
  if (written != n) {
    _free_unchecked(string);
    return NULL;
  }
  return _finish(string, n);
}

/* One conversion specification: the flag bits, the width and precision with
   their presence, a length modifier, and the conversion byte. */
typedef struct _Spec {
  int flags, width, precision, has_width, has_precision, modifier;
  char conversion;
} _Spec;

// The flag bits of `-+ #0`, in that order.
enum {
  FORMAT_LEFT = 1, FORMAT_PLUS = 2, FORMAT_SPACE = 4, FORMAT_ALT = 8,
  FORMAT_ZERO = 16
};

// The length modifiers `hh h l ll L`; zero is none.
enum {
  FORMAT_HH = 1, FORMAT_H = 2, FORMAT_L = 3, FORMAT_LL = 4, FORMAT_CAP_L = 5
};

/* One pass of `String.format`. The bytes from `literal` to `cursor` are
   text not yet written, `offset` is the `%` of the conversion being read,
   which its errors report, and `args` holds the values still to take. */
typedef struct _Format {
  String fmt, int length, literal, cursor, offset, List args, Buffer out;
} _Format;

/** Formats `values` through a checked, C-style subset of `fmt`.
    The receiver is decoded runtime text, so this fixed-signature operation is
    safe to call through the interpreter as `fmt.format(values)`. It supports
    `%%`, flags `-+ #0`, numeric or `*` width and precision, integer
    conversions `d i o u x X` with `hh h l ll`, floating conversions
    `f F e E g G a A` with default, `l`, or `L`, and `%c` and `%s`.
    Numeric values are converted with `Var.convert`; `%s` uses `Var.str`.

    Pointer and write-count conversions, wide strings and characters,
    positional arguments, `j z t` lengths, malformed formats, and missing or
    excess values are rejected. `%c` also rejects NUL because canonical
    `String`s cannot contain it. Output is staged privately and no result is
    published on failure. Formatting follows the process locale.

    Raises: `<format>` with byte `offset` and `reason`; numeric and string
    conversion failures are nested as `cause`. Allocation failures may also
    transfer while staging or canonicalizing the result.
*/
String String.format(String fmt, List values) {
  if (!fmt || !*fmt) {
    if (values) _format_error(0, "excess values");
    return NULL;
  }
  Buffer out = $auto(Buffer.new(0));
  _Format f = {.fmt = fmt, .length = fmt.len(), .args = values, .out = out};
  while (f.cursor < f.length)
    if (f.byte() == '%') f.conversion();
    else f.cursor++;
  f.write_literal();
  if (f.args) _format_error(f.length, "excess values");
  return out;
}

/* Writes the text before the `%` at the cursor, then the conversion that
   `%` starts. */
static void _Format.conversion(_Format *f) {
  f.write_literal();
  f.offset = f.cursor++;
  f.need_byte();
  if (f.byte() == '%') {
    f.out.write_char('%');
    f.cursor++;
  }
  else {
    _Spec spec = f.spec();
    f.print(spec, f.take("missing value"));
  }
  f.literal = f.cursor;
}

static void _Format.write_literal(_Format *f) {
  f.out.write_len(f.fmt + f.literal, (size_t) (f.cursor - f.literal));
}

static void _format_error(int offset, String reason) {
  raise %(format (offset $offset) (reason $reason));
}

static void _Format.fail(_Format *f, String reason) {
  _format_error(f.offset, reason);
}

/* A conversion that reaches the end of the format is incomplete. */
static void _Format.need_byte(_Format *f) {
  if (f.cursor == f.length) f.fail("incomplete conversion");
}

// conversion specifications

/* Parses the flags, width, precision, length modifier, and conversion
   after `%`, then rejects what the checked subset leaves out. */
static _Spec _Format.spec(_Format *f) {
  _Spec spec = {.flags = f.flags()};
  f.width(spec);
  f.precision(spec);
  f.need_byte();
  spec.modifier = f.modifier();
  f.need_byte();
  spec.conversion = f.fmt[f.cursor++];
  f.check(spec);
  return spec;
}

static int _Format.flags(_Format *f) {
  int flags = 0;
  for (;;) {
    switch (f.byte()) {
      case '-': flags |= FORMAT_LEFT; break;
      case '+': flags |= FORMAT_PLUS; break;
      case ' ': flags |= FORMAT_SPACE; break;
      case '#': flags |= FORMAT_ALT; break;
      case '0': flags |= FORMAT_ZERO; break;
      default: return flags;
    }
    f.cursor++;
    f.need_byte();
  }
}

/* A `*` width takes the next value, and a negative one also sets `-`. */
static void _Format.width(_Format *f, _Spec &spec) {
  if (f.byte() == '*') {
    int width = f.star();
    if (width == INT_MIN) f.fail("width exceeds int range");
    if (width < 0) {
      spec.flags |= FORMAT_LEFT;
      width = -width;
    }
    spec.has_width = 1;
    spec.width = width;
    f.cursor++;
  }
  else if (f.digit()) {
    spec.has_width = 1;
    spec.width = f.decimal("width");
  }
}

/* A `*` width or precision is the next value as an int. */
static int _Format.star(_Format *f) =>
  (int) f.number(f.take("missing star value"), <i32>).integer();

/* A `*` precision takes the next value, and a negative one means none. */
static void _Format.precision(_Format *f, _Spec &spec) {
  if (f.cursor >= f.length || f.byte() != '.') return;
  spec.has_precision = 1;
  f.cursor++;
  f.need_byte();
  if (f.byte() == '*') {
    int precision = f.star();
    if (precision < 0) spec.has_precision = 0;
    else spec.precision = precision;
    f.cursor++;
  }
  else if (f.digit()) spec.precision = f.decimal("precision");
}

/* Reads the digits at the cursor. An overflow reports the offset of the
   first digit and names the field with `label`. */
static int _Format.decimal(_Format *f, String label) {
  int number = 0, start = f.cursor;
  while (f.cursor < f.length && f.digit()) {
    int digit = f.byte() - '0';
    if (number > (INT_MAX - digit) / 10)
      _format_error(start, %"$label exceeds int range");
    number = number * 10 + digit;
    f.cursor++;
  }
  return number;
}

static int _Format.byte(_Format *f) => f.fmt[f.cursor];

static int _Format.digit(_Format *f) => f.byte() >= '0' && f.byte() <= '9';

static int _Format.modifier(_Format *f) {
  switch (f.byte()) {
    case 'h': return f.doubled('h', FORMAT_H, FORMAT_HH);
    case 'l': return f.doubled('l', FORMAT_L, FORMAT_LL);
    case 'L': f.cursor++; return FORMAT_CAP_L;
    case 'j': case 'z': case 't': f.fail("unsupported length modifier");
  }
  return 0;
}

/* `h` or `hh`, and `l` or `ll`. */
static int _Format.doubled(_Format *f, char letter, int once, int twice) {
  f.cursor++;
  if (f.cursor >= f.length || f.byte() != letter) return once;
  f.cursor++;
  return twice;
}

/* Rejects the conversions and combinations the checked subset leaves out,
   in this order. */
static void _Format.check(_Format *f, _Spec spec) {
  char ch = spec.conversion;
  int integer = strchr("diouxX", ch) != NULL;
  int floating = strchr("fFeEgGaA", ch) != NULL, text = ch == 'c' || ch == 's';
  if (ch == '$') f.fail("positional formats are unsupported");
  if (!integer && !floating && !text) f.fail("unsupported conversion");
  if (integer && spec.modifier == FORMAT_CAP_L)
    f.fail("unsupported integer length");
  if (floating && spec.modifier && spec.modifier != FORMAT_L &&
      spec.modifier != FORMAT_CAP_L)
    f.fail("unsupported floating length");
  if (text && spec.modifier)
    f.fail("wide strings and characters are unsupported");
  if (text && (spec.flags & ~FORMAT_LEFT))
    f.fail("unsupported flag for conversion");
  if (ch == 'c' && spec.has_precision) f.fail("unsupported precision for %c");
}

// conversion arguments

/* The next argument, or a failure with `reason` when none is left. */
static Var _Format.take(_Format *f, String reason) {
  if (!f.args) f.fail(reason);
  Var arg = f.args.car();
  f.args = f.args.cdr();
  return arg;
}

/* Prints `arg` through the C spelling of `spec`. The check leaves only
   these conversions, so the floating ones are the rest. */
static Buffer _Format.print(_Format *f, _Spec spec, Var arg) {
  char text[48];
  spec.spell(text);
  switch (spec.conversion) {
    case 'd': case 'i': return f.signed_int(text, spec.modifier, arg);
    case 'o': case 'u': case 'x': case 'X':
      return f.unsigned_int(text, spec.modifier, arg);
    case 'c': return f.character(text, arg);
    case 's': return f.string(text, arg);
  }
  return f.floating(text, spec.modifier, arg);
}

/* Writes the C spelling of `s`, with `*` values as numbers. */
static void _Spec.spell(_Spec s, char *out) {
  int n = 0;
  out[n++] = '%';
  if (s.flags & FORMAT_LEFT) out[n++] = '-';
  if (s.flags & FORMAT_PLUS) out[n++] = '+';
  if (s.flags & FORMAT_SPACE) out[n++] = ' ';
  if (s.flags & FORMAT_ALT) out[n++] = '#';
  if (s.flags & FORMAT_ZERO) out[n++] = '0';
  if (s.has_width && s.width) n += snprintf(out + n, 16, "%d", s.width);
  if (s.has_precision) {
    out[n++] = '.';
    n += snprintf(out + n, 16, "%d", s.precision);
  }
  switch (s.modifier) {
    case FORMAT_HH: out[n++] = 'h'; out[n++] = 'h'; break;
    case FORMAT_H: out[n++] = 'h'; break;
    case FORMAT_L: out[n++] = 'l'; break;
    case FORMAT_LL: out[n++] = 'l'; out[n++] = 'l'; break;
    case FORMAT_CAP_L: out[n++] = 'L'; break;
  }
  out[n++] = s.conversion;
  out[n] = '\0';
}

/* Integer conversions print a long or a long long for `l` and `ll`, and
   otherwise an int or unsigned holding the value at the modifier's width. */
static Buffer _Format.signed_int(
  _Format *f, const char *text, int modifier, Var arg) {
  switch (modifier) {
    case FORMAT_L:
      return f.out.printf(text, f.number(arg, <long>).long_value());
    case FORMAT_LL:
      return f.out.printf(text, f.number(arg, <llong>).long_long_value());
  }
  return f.out.printf(text, f.narrow_signed(arg, modifier));
}

static int _Format.narrow_signed(_Format *f, Var arg, int modifier) {
  switch (modifier) {
    case FORMAT_HH: return (signed char) f.number(arg, <i8>).integer();
    case FORMAT_H: return (short) f.number(arg, <i16>).integer();
  }
  return (int) f.number(arg, <i32>).integer();
}

static Buffer _Format.unsigned_int(
  _Format *f, const char *text, int modifier, Var arg) {
  switch (modifier) {
    case FORMAT_L:
      return f.out.printf(text, f.number(arg, <ulong>).ulong_value());
    case FORMAT_LL:
      return f.out.printf(text, f.number(arg, <ullong>).ulong_long_value());
  }
  return f.out.printf(text, f.narrow_unsigned(arg, modifier));
}

static unsigned _Format.narrow_unsigned(_Format *f, Var arg, int modifier) {
  switch (modifier) {
    case FORMAT_HH: return (unsigned char) f.number(arg, <u8>).integer();
    case FORMAT_H: return (unsigned short) f.number(arg, <u16>).integer();
  }
  return (unsigned int) f.number(arg, <u32>).integer();
}

/* `L` prints a long double, and the other modifiers a double. */
static Buffer _Format.floating(
  _Format *f, const char *text, int modifier, Var arg) {
  if (modifier == FORMAT_CAP_L)
    return f.out.printf(text, f.number(arg, <ldouble>).long_double_value());
  return f.out.printf(text, f.number(arg, <f64>).floating());
}

static Buffer _Format.character(_Format *f, const char *text, Var arg) {
  int byte = (int) f.number(arg, <i32>).integer();
  if (!(unsigned char) byte) f.fail("%c cannot produce an embedded NUL");
  return f.out.printf(text, byte);
}

static Buffer _Format.string(_Format *f, const char *text, Var arg) {
  String string = f.text(arg);
  return f.out.printf(text, string ? string : "");
}

/* Converts `arg` to the numeric `target`, nesting a failure's cause. */
static Var _Format.number(_Format *f, Var arg, Symbol target) {
  Var converted = void;
  try converted = arg.convert(target);
  catch %(?code *details): f.nested("value conversion failed", code, details);
  return converted;
}

/* The display text of `arg`, nesting a failure's cause. */
static String _Format.text(_Format *f, Var arg) {
  String converted = NULL;
  try converted = arg.str();
  catch %(?code *details): f.nested("string conversion failed", code, details);
  return converted;
}

/* Raises `<format>` for the current conversion with the cause of a failed
   conversion nested. */
static void _Format.nested(_Format *f, String reason, Var code, List details) {
  List cause = cons(code, details);
  raise %(format (offset ${f.offset}) (reason $reason) (cause $cause));
}

// escapes

/** Returns a canonical escaped representation of the bytes in `str`.
    Common control and delimiter bytes use named escapes, printable ASCII is
    copied, and every other byte uses a three-digit octal escape. `Null`
    input or an oversized result returns NULL.
    Raises: `<alloc-fail>` while constructing the result.
*/
meta native String String.escape(String str) {
  if (!str) return NULL;
  int bytes = 0;
  foreach (int byte, str) {
    int width = _escape_byte((unsigned char) byte, NULL);
    if (bytes > INT_MAX - width - 1) return NULL;
    bytes += width;
  }
  String string = String.malloc(bytes + 1), char *dst = string;
  foreach (int byte, str) dst += _escape_byte((unsigned char) byte, dst);
  return _finish(string, bytes);
}

/* Writes the escape of `ch` to `out` unless `out` is NULL, and returns its
   width: a named escape, the printable byte itself, or an octal escape. */
static inline int _escape_byte(unsigned char ch, char *out) {
  char letter = _escape_letter(ch);
  if (letter) {
    if (out) {
      out[0] = '\\';
      out[1] = letter;
    }
    return 2;
  }
  if (ch >= 32 && ch <= 126) {
    if (out) out[0] = ch;
    return 1;
  }
  if (out) {
    out[0] = '\\';
    out[1] = ((ch >> 6) & 0x03) + '0';
    out[2] = ((ch >> 3) & 0x07) + '0';
    out[3] = (ch & 0x07) + '0';
  }
  return 4;
}

/* The letter of the named escape for `ch`, or 0 when it has none. */
static inline char _escape_letter(unsigned char ch) {
  switch (ch) {
    case '\n': return 'n';
    case '\r': return 'r';
    case '\t': return 't';
    case '\b': return 'b';
    case '\f': return 'f';
    case '\v': return 'v';
    case '\\': return '\\';
    case '"':  return '"';
    case '\'': return '\'';
  }
  return 0;
}

/** Decodes supported backslash escapes in `str` into a canonical `String`.
    Standard single-byte escapes, up to two hexadecimal digits after `x`, `u`,
    or `U`, and up to three octal digits are consumed. A backslash-newline is
    removed, an unknown escape yields its following byte, and a trailing
    backslash is dropped. `Null` input returns NULL and input without a
    backslash is returned unchanged.
    Raises: `<bad-arg>` for an octal escape above `\377`, which does not fit
    a byte, or `<alloc-fail>` while constructing a changed result.
*/
meta native String String.unescape(String str) {
  int n = str.len();
  if (n == 0) return NULL;
  if (!str.contains("\\")) return str;
  String string = String.malloc(n + 1);
  int length = _unescape_into(string, str);
  if (length < 0) {
    _free_unchecked(string);
    raise %(bad-arg (owner "String.unescape"));
  }
  return _finish(string, length);
}

/* Decodes the escapes of `src` into `out` and returns the bytes written, or
   -1 at an octal escape above `\377`. A trailing backslash is dropped. */
static int _unescape_into(char *out, const char *src) {
  char *dst = out;
  while (*src) {
    if (*src != '\\') {
      *dst++ = *src++;
      continue;
    }
    src++;
    if (!*src) break;
    int byte = _decode_escape(src);
    if (byte > 0377) return -1;
    if (byte > 0) *dst++ = byte;
  }
  return (int) (dst - out);
}

/* Decodes the escape after a backslash and advances `at` past it. Returns
   its byte, a value above `\377` for an octal escape too large for a byte,
   or -1 for a backslash-newline, which stands for no byte. */
static inline int _decode_escape(const char *&at) {
  int esc = (unsigned char) *at++;
  switch (esc) {
    case 'x': case 'X': case 'u': case 'U': return _hex_escape(at, esc);
    case '0': case '1': case '2': case '3':
    case '4': case '5': case '6': case '7': return _octal_escape(at, esc);
    case '\n': return -1;
  }
  return _named_escape(esc);
}

/* Up to two hexadecimal digits; with none, the escape is its letter. */
static inline int _hex_escape(const char *&at, int esc) {
  int byte = 0, digits = 0;
  for (; *at && digits < 2; at++, digits++) {
    int hex = _hex_digit(*at);
    if (hex < 0) break;
    byte = (byte << 4) | hex;
  }
  return digits ? byte : esc;
}

static inline int _hex_digit(int ch) {
  if (ch >= '0' && ch <= '9') return ch - '0';
  if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
  if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
  return -1;
}

/* Up to three octal digits, the first of them `esc`. */
static inline int _octal_escape(const char *&at, int esc) {
  int byte = esc - '0';
  for (int digits = 1; *at && digits < 3; at++, digits++) {
    char next = *at;
    if (next < '0' || next > '7') break;
    byte = (byte << 3) | (next - '0');
  }
  return byte;
}

/* A letter escape's control byte. Every other escaped byte, such as `\\`,
   `\"`, or `\$`, stands for itself. */
static inline int _named_escape(int esc) {
  switch (esc) {
    case 'a': return '\a';
    case 'b': return '\b';
    case 'f': return '\f';
    case 'n': return '\n';
    case 'r': return '\r';
    case 't': return '\t';
    case 'v': return '\v';
  }
  return esc;
}

/** Parses one leading single-quoted escaped or literal byte, or returns -1.
    The opening quote, one decoded byte, and a closing quote are required.
    Text after that closing quote is ignored. A decoded NUL is returned as
    zero; malformed and null input returns -1, as does an octal escape above
    `\377`, which does not fit a byte.
*/
meta native int String.parse_char(String str) {
  if (!str || !*str) return -1;
  const char *at = str;
  if (*at++ != '\'' || !*at) return -1;
  int byte = *at++;
  if (byte == '\\') {
    if (!*at) return -1;
    byte = _decode_escape(at);
    if (byte < 0 || byte > 0377) return -1;
  }
  return *at == '\'' ? byte : -1;
}

/** Returns the canonical unescaped contents of `str`.
    Matching outer `%"..."` or `"..."` delimiters are removed; unquoted input
    is unescaped directly. `Null` or empty input returns NULL. An unquoted
    input without backslashes is returned unchanged.
    Raises: `<alloc-fail>` while copying or decoding.
*/
meta native String String.parse(String str) {
  if (!str || !*str) return NULL;
  int n = str.len();
  if (str[0] == '%' && str[1] == '"' && str[n - 1] == '"')
    return String.new_len(str + 2, n - 3).unescape();
  if (str[0] == '"' && str[n - 1] == '"')
    return String.new_len(str + 1, n - 2).unescape();
  return str.unescape();
}

// conversions

/** Returns `str` itself as its display `String` without copying or retaining
    it.
*/
String String.str(String str) => str;

/** Returns a canonical quoted and escaped representation of `str`.
    Empty input returns the canonical literal spelling `"\"\""`.
    Raises: `<alloc-fail>` while escaping or formatting a nonempty `String`.
*/
String String.repr(String str) {
  if (!str || !*str) return "\"\"";
  return "\"%s\"".printf(str.escape());
}

/** Appends `str` to `out` unchanged.
    A `String` is already its own display text, so this writes it directly
    instead of routing through `String.str`. `Null` `str` is a no-op. The
    borrowed `out` is returned and not retained.
    Raises: any cause from `Buffer.write`.
*/
Buffer String.write_str(String str, Buffer out) => str ? out.write(str) : out;

/** Appends a quoted escaped representation of `str` to borrowed `out`.
    Bytes are streamed without first allocating an intermediate `String`. The
    same `out` is returned and not retained. Text written before a failure
    remains in the `Buffer`.
    Raises: any cause from `Buffer.write_char` or `Buffer.write_len`.
*/
Buffer String.write_repr(String str, Buffer out) {
  out.write_char('"');
  foreach (int byte, str) {
    char escaped[4];
    int width = _escape_byte((unsigned char) byte, escaped);
    out.write_len(escaped, width);
  }
  return out.write_char('"');
}

/** Returns the compact `Symbol` encoded from `str`, or zero for empty input.
    `Symbol`'s restricted spelling folds case and `_` with `-`; other spellings
    use seven-bit bytes, and input beyond the selected encoding's capacity is
    truncated. Use `Symbol.try_new` when every byte must be preserved.
*/
meta native Symbol String.symbol(String str) {
  if (!str || !*str) return 0;
  return Symbol.new(str);
}

// iteration

/** Initializes `dest` as a lazy iterator over the bytes of `x`.
    The caller owns `dest`; it borrows `x`, which must remain live through
    traversal. A null `dest` returns NULL, and null `x` is exhausted. Each pull
    yields the next byte as an `<i32>` `Var` in index order. The function
    retains neither argument.
    Foreach may convert each yielded byte to either `int` or `char`:

    ```x2c
    foreach (int byte, "abc") printf("%d\n", byte);
    foreach (char ch, "abc") printf("%c\n", ch);
    ```

    This is byte traversal, not Unicode character iteration.
*/
Iter String.iter(String x, Iter dest) {
  if (!dest) return NULL;
  return dest.init(x, _next, 0);
}

static int _next(Iter iter, Var *out) {
  int index = iter.state, String str = iter.obj;
  if (index < 0 || index >= str.len()) return 0;
  *out = str[index];
  iter.state = index + 1;
  return 1;
}

/** Writes the next byte, advances `cursor`, and returns one.
    Initialize the caller-owned cursor to zero. A null `String`, a null
    pointer, a negative cursor, or exhaustion returns zero without changing
    `cursor` or `out`. This is byte traversal, not Unicode characters.

    `foreach (int byte, str)` and `foreach (char ch, str)` compile to this
    loop.
*/
int String.try_next(String str, int &?cursor, int &?out) {
  if (!cursor) return 0;
  if (!out) return 0;
  if (!str || cursor < 0) return 0;
  if (cursor >= str.len()) return 0;
  out = str[cursor];
  cursor += 1;
  return 1;
}
