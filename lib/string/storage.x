/*  storage.x -- String storage operations */

// representation

/* `length` includes the trailing NUL. A zero hash marks an unfinished
   String.malloc buffer; canonical nonempty Strings have their content hash
   installed before entering a pool table. */
static typedef struct StringHeader {
  int length;
  unsigned hash;
} *StringHeader;

/* Canonical String payloads are custom-object-safe: Scope allocations are
   max-aligned and the payload begins eight bytes after the base. */
_Static_assert(
  sizeof(struct StringHeader) == 8,
  "the String header is 8 bytes, so payloads stay aligned");

/* Small construction buffers and lookup-before-allocation share this limit. */
#define STRING_STACK_BYTES 256

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
  // `!str` also reads the first byte, which a fresh buffer leaves unset.
  if (str == NULL) return 0;
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
  if (!x || !y) return !x && !y;
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
  if (!x) return y ? -1 : 0;
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
  return x2c_string_from_bytes(str, (int) length);
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
  return x2c_string_from_bytes(str, (int) length);
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

/** Canonicalizes a known NUL-free byte span in the active pool chain.
    Copies bytes only when needed; the caller retains its input storage.
    Null input or a nonpositive length returns the empty String.
    Raises alloc-fail if canonical storage cannot be allocated. */
String x2c_string_from_bytes(const char *bytes, int length) =>
  _from_bytes_in(Pool.current(), bytes, length);

/* A short `String` probes the whole ancestor chain from borrowed bytes before
   anything is allocated, and a miss is installed in `pool`. A long one is
   stored first, and Pool.intern releases that candidate on a hit. */
static String _from_bytes_in(Pool pool, const char *bytes, int length) {
  if (!pool || !bytes || length <= 0) return NULL;
  unsigned hash = _hash_n(bytes, length);
  if (length <= STRING_STACK_BYTES) {
    String existing = x2c_pool_lookup_string(pool, bytes, length, hash);
    if (existing) return existing;
  }
  size_t total = sizeof(struct StringHeader) + (size_t) length + 1;
  StringHeader header = pool.malloc(total);
  String string = _store(header, bytes, length, hash);
  if (length > STRING_STACK_BYTES) return pool.intern(string, header);
  pool.insert(string);
  return string;
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
module String _finish(String string, int length) {
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
  String found = x2c_pool_lookup_string(
    pool, string, header.length - 1, header.hash);
  if (!found) {
    pool.insert(string);
    return string;
  }
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
module void _free_unchecked(String str) {
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
module int _is_active_canonical(String str) =>
  Pool.current().lookup(str) === str;
