/*  editing.x -- String editing operations */

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
    int prefix_len = found - (str + copied);
    memcpy(dst, str + copied, prefix_len);
    dst += prefix_len;
    if (replacement_len) {
      memcpy(dst, replacement, replacement_len);
      dst += replacement_len;
    }
    copied = found - str + old_len;
    replaced++;
  }
  memcpy(dst, str + copied, str_len - copied);
  return _finish(string, length);
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
  int n = s.len(), len = x2c_normalize_slice(start, stop, step, n);
  if (len <= 0) return NULL;
  if (step == 1 && start == 0 && len == n && _is_active_canonical(s)) return s;
  if (step == 1) return x2c_string_from_bytes(s + start, len);
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
    raise %(bad-arg (operation "String.withindex") (index $index));
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
