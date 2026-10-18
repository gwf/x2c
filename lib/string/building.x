/*  building.x -- String building operations */

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
  if (fill == '\0') raise %(bad-arg (operation "String.new_fill"));
  if (count == INT_MAX)
    raise %(size-limit (operation "String.new_fill") (count $count));
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
  if (fill == '\0') raise %(bad-arg (operation "String.pad"));
  int length = str.len();
  if (width <= length) return str;
  if (width == INT_MAX)
    raise %(size-limit (operation "String.pad") (width $width));
  int padding = width - length, left = side ? padding : 0;
  if (side < 0) left = padding / 2;
  int right = padding - left, String string = String.malloc(width + 1);
  memset(string, fill, left);
  if (length) memcpy(string + left, str, length);
  memset(string + left + length, fill, right);
  return _finish(string, width);
}

/** Formats a canonical `String` from `fmt` and the trailing arguments.
    The receiver is the format `String`, so format-dependent construction reads
    `%"%-12s %.2f".printf(name, score)`. Conversions, promotion rules, and
    argument matching are C's, since the work is done by `vsnprintf`;
    canonical `String`s are NUL-terminated and satisfy `%s` directly. Prefer
    `%"$name has ${name.len()} bytes"` when interpolation already says what
    you want, and `String.format` when the arguments must be checked.
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
