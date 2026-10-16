/*  mapping.x -- String mapping operations */

// byte maps

/* Builds a same-length copy whose byte `$index` is `$mapped`, with the
   source byte offered as `$byte` so each family member gives only its own C
   case mapping. A copy that changes nothing is released and `$subject`
   itself is returned. */
static macro Stmt $string.remap(
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
static macro Stmt $string.select(
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
    Each byte is boxed from `char` and passed by value. A null or empty `str`
    returns `str` without invoking the callback. Otherwise `fn`
    is called once per byte from left to right and is not retained.
    A null `fn` raises `<bad-arg>` on the first invocation.
    Raises: whatever `Func.apply`, `fn`, or the returned `Var`'s truth
    operation raises, or `<alloc-fail>` when the result cannot be allocated.
*/
String String.filter(String str, Func fn) {
  if (!str || !*str) return str;
  $string.select(str, i, fn.apply_value((char) str[i]));
}

/** Returns `str` with `fn` applied to every byte.
    Each byte is boxed from `char` and passed by value. Each result is
    converted to `int` and truncated to the byte that is stored, and that byte
    is what is checked, so a result such as 256 raises because its stored byte
    would be NUL.
    A null or empty `str` returns `str` without invoking the callback.
    Otherwise `fn` is called once per byte from left to right and is
    not retained. Each result must convert to a non-NUL byte.
    A null `fn` raises `<bad-arg>` on the first invocation.
    Raises: whatever `Func.apply`, `fn`, or result conversion raises,
    `<bad-result>` when the converted result is zero, or `<alloc-fail>` when
    the result cannot be allocated.
*/
String String.map(String str, Func fn) {
  if (!str || !*str) return str;
  int n = str.len(), done = 0;
  String string = String.malloc(n + 1);
  defer if (!done) string.free();
  char *out = string, const char *src = str;
  for (int i = 0; i < n; i++) {
    char ch = (char) fn.apply_value(src[i]);
    if (!ch) raise %(bad-result (operation "String.map") (index $i));
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
