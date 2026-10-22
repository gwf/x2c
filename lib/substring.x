/*  substring.x -- borrowed immutable views of String bytes */

#pragma once
#include "string/string.x"

/** A borrowed immutable range of a String. Assignment copies the view and
    allocates nothing. Keep the source alive and unchanged through every use;
    use str() or string() to obtain a canonical String in the active pool chain.
    Construct views through Substring.new or String.substring. */
typedef struct Substring {
  String source;
  int offset, length;
} Substring;

typedef Substring Substr;

/** Borrows length bytes starting at offset. An invalid range raises bad-arg. */
Substring Substring.new(String source, int offset, int length) {
  if (offset < 0 || length < 0 || offset > source.len() ||
      length > source.len() - offset)
    raise %(bad-arg (operation "Substring.new") (offset $offset) (length $length));
  return (Substring) {source, offset, length};
}

/** Returns a borrowed immutable view of the requested byte range. */
Substring String.substring(String source, int offset, int length) =>
  Substring.new(source, offset, length);

/** Returns the byte length without allocating. */
inline int Substring.len(Substring view) => view.length;

/** Hashes the referenced bytes, independent of their source or offset. */
inline unsigned Substring.hash(Substring view) => view.length
  ? x2c_hash_bytes(0, (const char *) view.source + view.offset, (size_t) view.length)
  : 0;

/** Compares contents without materializing either view. */
inline int Substring.equal(Substring left, Substring right) =>
  left.length == right.length && (!left.length ||
    memcmp((const char *) left.source + left.offset,
           (const char *) right.source + right.offset, (size_t) left.length) == 0);

/** Compares contents in bytewise lexical order. */
inline int Substring.compare(Substring left, Substring right) {
  int length = left.length < right.length ? left.length : right.length;
  int order = length ? memcmp((const char *) left.source + left.offset,
    (const char *) right.source + right.offset, (size_t) length) : 0;
  return order ? (order > 0 ? 1 : -1) : left.length - right.length;
}

/** Materializes a canonical String in the active pool. Repeated conversion
    reuses the canonical value. The result follows its actual owning pool. */
String Substring.str(Substring view) => view.length
  ? x2c_string_from_bytes((const char *) view.source + view.offset, view.length) : NULL;

/** Materializes the same canonical String as str(). */
String Substring.string(Substring view) => view.str();

/** Yields the next word view. Start the caller-owned cursor at zero. The
    source must stay live; exhaustion leaves cursor and out unchanged.
    foreach (Substr word in source) uses this allocation-free cursor. */
int Substring.try_next(String source, int &cursor, Substring &out) {
  const char *bytes = source;
  int length = source.len(), index = cursor;
  while (index < length && isspace((unsigned char) bytes[index])) index++;
  if (index >= length) return 0;
  int start = index;
  while (index < length && !isspace((unsigned char) bytes[index])) index++;
  out = (Substring) {source, start, index - start};
  cursor = index;
  return 1;
}
