/*  search.x -- String search operations */

// search

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

/** Returns the index of the first occurrence of `sub` in `str`, or -1.
    The search compares bytes, so an index may land inside a multibyte
    sequence. An empty `sub` matches at index 0. Use `String.find_within` to
    bound the search to a range, or `String.rfind` to scan from the end.
*/
meta native int String.find(String str, String sub) =>
  str.find_within(sub, 0, -1);

/** Returns the first index of `sub` within `str[start:end]`, or -1.
    The returned index is absolute and counts from the start of `str`.
    `start` and `end` are normalized as slice bounds and then clamped to the
    `String`: a negative `start` counts from the end, and a negative `end`
    counts endpoints from the end, so -1 is the length of `str` and -2 omits
    its last byte. An empty `sub` matches at the normalized `start` unless
    `end` comes before it.

    ```x2c
    ~String text = "abcabc";
    printf("%d %d %d\n", text.find_within("c", 0, -1),
           text.find_within("c", 0, 2), text.find_within("a", -3, -1));
    ```
*/
meta native int String.find_within(
  String str, String sub, int start, int end) {
  int m = sub.len();
  x2c_normalize_slice(start, end, 1, str.len());
  if (start + m > end) return -1;
  if (m == 0) return start;
  const char *p = _find_bytes(str + start, end - start, sub, m);
  return p ? p - str : -1;
}

/** Reports whether `str` starts with any supplied prefix.
    No prefixes returns false. An empty prefix matches every String.
    Arguments and splices are evaluated once in order before matching.
*/
meta native int String.startswith(String str, List @prefixes) {
  int length = str.len();
  foreach (String prefix in prefixes) {
    int count = prefix.len();
    if (!count || (str && count <= length && !memcmp(str, prefix, count)))
      return 1;
  }
  return 0;
}

/** Reports whether `str` ends with any supplied suffix.
    No suffixes returns false. An empty suffix matches every String.
    Matching is bytewise and case-sensitive. Arguments and splices are
    evaluated once in order before matching.
*/
meta native int String.endswith(String str, List @suffixes) {
  int length = str.len();
  foreach (String suffix in suffixes) {
    int count = suffix.len();
    if (!count || (str && count <= length &&
                   !memcmp(str + length - count, suffix, count))) return 1;
  }
  return 0;
}

module const char *_find_bytes(
  const char *haystack, int haystack_len, const char *needle, int needle_len) {
  if (needle_len == 0) return haystack;
  if (!haystack || haystack_len < needle_len) return NULL;
  for (int i = 0; i <= haystack_len - needle_len; i++)
    if ((unsigned char) haystack[i] == (unsigned char) needle[0] &&
        memcmp(haystack + i, needle, needle_len) == 0)
      return haystack + i;
  return NULL;
}

/* Counts non-overlapping occurrences of `sub` in `str`, left to right, up to
   `limit` of them; a negative `limit` counts every match. */
module int _count_matches(String str, String sub, int limit) {
  int str_len = str.len(), sub_len = sub.len(), count = 0, pos = 0;
  while (pos <= str_len - sub_len && (limit < 0 || count < limit)) {
    const char *found = _find_bytes(str + pos, str_len - pos, sub, sub_len);
    if (!found) break;
    count++;
    pos = found - str + sub_len;
  }
  return count;
}
