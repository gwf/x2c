/*  splitting.x -- String splitting operations */

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
  if (!sep) return $(str, empty, empty);
  int sep_length = sep.len(), found = str.find(sep);
  if (found < 0) return $(str, empty, empty);
  String before = String.new_len(str, found);
  String after = String.new_len(
    str + found + sep_length, str.len() - found - sep_length);
  return $(before, sep, after);
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
  if (!sep) return $(empty, empty, str);
  int sep_length = sep.len(), found = str.rfind(sep);
  if (found < 0) return $(empty, empty, str);
  String before = String.new_len(str, found);
  String after = String.new_len(
    str + found + sep_length, str.len() - found - sep_length);
  return $(before, sep, after);
}
