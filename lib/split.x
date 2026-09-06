/*  split.x -- `String` field splitting and repeatable typed cursors

    Copyright (c) 2025 Gary William Flake

    A Split description is immutable and `Scope`-owned. It keeps no position;
    the caller holds the cursor, so one Split supports repeated, nested, and
    concurrent walks. Eager and lazy splitting share the same separator and
    line-ending scans.
*/

#pragma once

#include "string.x"

/** Describes an immutable, repeatable lazy traversal of a borrowed `String`.
    The descriptor is `Scope`-owned and keeps no position; each caller or
    `Iter`
    keeps its own cursor. The input and separator are not retained, so their
    actual `String` pools must remain live through every traversal. No cleanup
    is needed before the descriptor's `Scope` is released.
*/
typedef struct Split *Split;

protocol Iter(Split);

#pragma private

#include <ctype.h>
#include <string.h>

#include "var.x"
#include "list.x"
#include "array.x"
#include "iter.x"
#include "scope.x"

struct Split {
  String str, sep;
  int (*next)(Split split, int *cursor, String *out);
};

static inline int _end(String str, String sep, int start, int *next) {
  int length = str.len();
  if (!str || start < 0 || start > length) return -1;
  if (!sep) {
    *next = -1;
    return length;
  }
  const char *found = strstr(str + start, sep);
  if (!found) {
    *next = -1;
    return length;
  }
  int end = (int) (found - str);
  *next = end + sep.len();
  return end;
}

static inline int _line_end(String str, int start, int keep_ends, int *next) {
  int length = str.len();
  if (!str || start < 0 || start >= length) return -1;
  int end = start;
  while (end < length && str[end] != '\n' && str[end] != '\r') end++;
  int ending = 0;
  if (end < length)
    ending = str[end] == '\r' && end + 1 < length && str[end + 1] == '\n'
      ? 2 : 1;
  *next = end + ending;
  return keep_ends ? *next : end;
}

/** Splits `str` at no more than `max_splits` separators.
    A negative limit splits every occurrence; zero returns `str` as one field.
    A null `str` returns `nil`. A null or empty `sep` returns `str` as one
    field.
    The canonical fields and `List` remain live until their actual `String` and
    `List` pools are released.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
List String.split_n(String str, String sep, int max_splits) {
  if (!str) return %();
  Array results = %[], int start = 0, splits = 0;
  while (start >= 0) {
    int next = -1;
    int end = max_splits >= 0 && splits >= max_splits
      ? str.len() : _end(str, sep, start, &next);
    String field = String.new_len(str + start, end - start);
    results.push(field);
    start = next;
    splits++;
  }
  return results.list_free();
}

/** Splits `str` on every occurrence of `sep` into a `List` of `String`s.
    Separators are not coalesced, so adjacent ones produce empty fields and
    the result holds one more element than the number of separators found.
    An empty field is the empty `String`, the null pointer. An empty or null
    `sep` yields a one-element `List` holding `str`, and splitting the empty
    `String` yields the empty `List`. The canonical fields and `List` remain
    live
    until their actual `String` and `List` pools are released.

    ```x2c
    printf("%s\n", %"a:b:c".split(":").repr());
    printf("%s\n", %"a::b".split(":").repr());
    ```
    Raises: the same causes as `String.split_n`.
*/
List String.split(String str, String sep) => str.split_n(sep, -1);

/** Splits `str` into a `List` of lines.
    LF, CR, and CRLF all end a line, and CRLF counts as one ending. A
    nonzero `keep_ends` leaves each line's ending attached to it. A trailing
    line ending does not produce a final empty line, so text that ends in a
    newline yields as many lines as it has endings. A null or empty `str`
    returns `nil`. The canonical fields and `List` remain live until their
    actual
    `String` and `List` pools are released.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing fields or the
    result.
*/
List String.split_lines(String str, int keep_ends) {
  if (!str) return %();
  Array results = %[], int start = 0;
  while (start < str.len()) {
    int next, end = _line_end(str, start, keep_ends, &next);
    String field = String.new_len(str + start, end - start);
    results.push(field);
    start = next;
  }
  return results.list_free();
}

static Split _new(
  String str, String sep, int (*next)(Split split, int *cursor, String *out)) {
  Split split = Scope.malloc(sizeof(struct Split));
  split.str = str;
  split.sep = sep;
  split.next = next;
  return split;
}

static int _words_next(Split split, int *cursor, String *out) {
  if (!split || !split.str) return 0;
  const char *p = split.str, int length = split.str.len(), index = *cursor;
  while (index < length && isspace((unsigned char) p[index])) index++;
  if (index >= length) return 0;
  int start = index;
  while (index < length && !isspace((unsigned char) p[index])) index++;
  String field = String.new_len(p + start, index - start);
  *out = field;
  *cursor = index;
  return 1;
}

static int _lines_next(Split split, int *cursor, String *out) {
  if (!split || !split.str) return 0;
  int start = *cursor, next, end = _line_end(split.str, start, 0, &next);
  if (end < 0) return 0;
  String field = String.new_len(split.str + start, end - start);
  *out = field;
  *cursor = next;
  return 1;
}

static int _splits_next(Split split, int *cursor, String *out) {
  if (!split || !split.str) return 0;
  int start = *cursor, next;
  int end = _end(split.str, split.sep, start, &next);
  if (end < 0) return 0;
  String field = String.new_len(split.str + start, end - start);
  *out = field;
  *cursor = next;
  return 1;
}

/** Returns a lazy cursor over whitespace-delimited words in `str`.
    Runs of C `isspace` bytes are coalesced, leading and trailing whitespace
    is ignored, and no empty `String` is yielded. `str.splits(" ")` instead
    preserves empty fields around every explicit separator.

    Each yielded field is a canonical `String`. Distinct fields remain resident
    in the active `String` pool; bracket bulk traversal with
    `String.pool_retain` / `String.pool_release` and promote retained values
    when that residency should be temporary. The cursor borrows `str`, whose
    actual owning pool must remain live through traversal.
    Raises: `<alloc-fail>` when the cursor descriptor cannot be allocated.
    An empty `String` produces an exhausted cursor.
*/
Split String.words(String str) => _new(str, NULL, _words_next);

/** Returns a lazy cursor over lines in `str`, with endings removed.
    LF, CR, and CRLF end a line, with CRLF counted as one ending. The yielded
    fields agree with `str.split_lines(0)`, including empty interior lines and
    the rule that a trailing ending does not add a final empty line.

    Each yielded field is a canonical `String`. Distinct fields remain resident
    in the active `String` pool; bracket bulk traversal with
    `String.pool_retain` / `String.pool_release` and promote retained values
    when that residency should be temporary. The cursor borrows `str`, whose
    actual owning pool must remain live through traversal.
    Raises: `<alloc-fail>` when the cursor descriptor cannot be allocated.
    An empty `String` produces an exhausted cursor.
*/
Split String.lines(String str) => _new(str, NULL, _lines_next);

/** Returns a lazy cursor over fields separated by `sep`.
    Separators are not coalesced, so adjacent separators produce empty
    fields. The yielded fields agree with `str.split(sep)`. A null or empty
    separator yields `str` once, while an empty `str` yields nothing.

    Each yielded field is a canonical `String`. Distinct fields remain resident
    in the active `String` pool; bracket bulk traversal with
    `String.pool_retain` / `String.pool_release` and promote retained values
    when that residency should be temporary. The cursor borrows `str` and
    `sep`; both actual owning pools must remain live through traversal.
    Raises: `<alloc-fail>` when the cursor descriptor cannot be allocated.
*/
Split String.splits(String str, String sep) => _new(str, sep, _splits_next);

/** Yields the next field and advances a caller-owned position on success.
    Position must start at zero and thereafter retain only values written by
    this method. Both it and `out` are written only on success, so an empty
    `String` field stays distinct from exhaustion and a walk that has ended
    leaves the last field in place. The position belongs to the caller, so one
    descriptor supports repeated, nested, and concurrent walks, including
    alongside a `Split.iter` iterator over the same descriptor. A yielded
    canonical `String` remains live until its actual owning pool is released.

    ```x2c
    Split words = %"ada lovelace".words();
    int cursor = 0;
    String word;
    while (words.try_next(&cursor, &word)) printf("%s\n", word);
    ```

    This is what `foreach(String word, split)` lowers to; `Split.iter` is the
    boxing adapter for every other binder.
    Raises: `<alloc-fail>` while canonicalizing a nonempty field. `Null`
    arguments produce exhaustion without raising.
*/
int Split.try_next(Split split, int *cursor, String *out) {
  if (!split || !cursor || !out || !split.next) return 0;
  return split.next(split, cursor, out);
}

static int _iter_next(Iter iter, Var *out) {
  Split split = iter.obj, int cursor = iter.state.int(), String value;
  if (!split.try_next(&cursor, &value)) return 0;
  iter.state = cursor;
  *out = value;
  return 1;
}

/** Returns an iterator over a lazy `String` cursor.
    This adapter over `Split.try_next` boxes each field into a `Var` and
    keeps the `Iter` state in step. Use the typed cursor in hot code and this
    method when you need the `Iter` protocol.

    The cursor descriptor is `Scope`-owned; `dest` is caller-supplied iterator
    storage. Every iterator keeps its own byte position, so cursors can be
    nested or traversed concurrently. The `Split` descriptor, its borrowed
    input `String`s, and `dest` must remain live until iteration ends.

    Constructing the iterator does not raise. Pulling may raise
    `<alloc-fail>` as `Split.try_next` does. A null `dest` returns NULL.
*/
Iter Split.iter(Split split, Iter dest) {
  if (!dest) return NULL;
  return dest.init((void *) split, split ? _iter_next : NULL, 0);
}
