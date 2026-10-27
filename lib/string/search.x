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
  return p - str;
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

static int _clamp(int index, int n) {
  if (index < 0) return 0;
  return index > n ? n : index;
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
