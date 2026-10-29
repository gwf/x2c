/*  encoding.x -- UTF-8 code points and base64, hex, and percent encodings

    Copyright (c) 2026 Gary William Flake

    A `String` holds bytes. The UTF-8 operations read and write the code
    points those bytes encode, and the byte encodings turn any bytes into
    ASCII text and back. A `String` cannot hold a NUL byte, so a decoder
    that returns a `String` raises `<malformed>` for one, and its `_bytes`
    form returns a `Block` of 1-byte elements instead. Invalid input raises
    `<malformed>` with the operation, a reason, and the byte `offset`.
*/

#pragma once
#include "x2c.x"

#include <string.h>

/* A base64 alphabet: its 64 digits and whether output ends with `=`
   padding to a multiple of four characters. */
static typedef struct Alphabet {
  const char *digits;
  int pad;
} Alphabet;

static const Alphabet _STANDARD = {
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", 1
};

static const Alphabet _URL = {
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", 0
};

// UTF-8 code points

/** Reports whether `text` is well-formed UTF-8, with no overlong form,
    surrogate, or code point above U+10FFFF. The empty `String` is.
*/
int String.is_utf8(String text) {
  for (const unsigned char *at = (const unsigned char *) text; at && *at;) {
    int length = scan_utf8_length(at);
    if (length < 0) return 0;
    at += length;
  }
  return 1;
}

/** Returns the number of code points that `text` encodes in UTF-8.
    Raises: `<malformed>` when `text` is not well-formed UTF-8.
*/
int String.code_point_count(String text) {
  int count = 0, cursor = 0, point;
  while (text.try_next_code_point(cursor, point)) count++;
  return count;
}

/** Decodes the code point that starts at byte `cursor` of `text` into
    `point`, advances `cursor` past it, and returns one. At the end of
    `text`, or for a negative `cursor`, it returns zero and changes
    nothing.

    ```x2c
    ~#include "encoding.x"
    ~int main(void) {
    String text = "na\xc3\xafve";
    int cursor = 0, point;
    while (text.try_next_code_point(cursor, point))
      printf("U+%04X ends at byte %d\n", point, cursor);
    ~  return 0;
    ~}
    ```

    Raises: `<malformed>` with `cursor` as the `offset` when the bytes there
    are not a well-formed UTF-8 sequence.
*/
int String.try_next_code_point(String text, int &cursor, int &point) {
  if (cursor < 0 || cursor >= text.len()) return 0;
  const unsigned char *at = (const unsigned char *) text + cursor;
  int length = scan_utf8_length(at);
  if (length < 0)
    _malformed("String.try_next_code_point", "invalid UTF-8", cursor);
  point = _decode_point(at, length);
  cursor += length;
  return 1;
}

/** Initializes `dest` as a lazy iterator over the code points of `text`,
    each yielded as an `int`, so `foreach (int point in text.code_points())`
    walks them. The iterator borrows `text`.
    Raises: `<malformed>` from the pull that reaches bytes that are not
    well-formed UTF-8.
*/
Iter String.code_points(String text, Iter dest) =>
  dest.init(text, _next_point, 0);

/** Appends the UTF-8 encoding of `point` to `out` and returns `out`.
    Raises: `<bad-arg>` when `point` is a surrogate, above U+10FFFF, or not
    positive; a `String` cannot hold U+0000.
*/
Buffer Buffer.write_code_point(Buffer out, int point) {
  static const unsigned char lead[] = {0, 0, 0xC0, 0xE0, 0xF0};
  if (point <= 0 || point > 0x10FFFF || (point >= 0xD800 && point <= 0xDFFF))
    raise %(bad-arg (operation "Buffer.write_code_point") (point $point));
  if (point < 0x80) return out.write_char(point);
  int length = 4;
  if (point < 0x800) length = 2;
  else if (point < 0x10000) length = 3;
  char bytes[4];
  for (int i = length - 1; i > 0; i--, point >>= 6)
    bytes[i] = 0x80 | (point & 0x3F);
  bytes[0] = lead[length] | point;
  return out.write_len(bytes, length);
}

/** Returns the `String` that encodes the one code point `point` in UTF-8.
    Raises: the causes of `Buffer.write_code_point`.
*/
String String.from_code_point(int point) {
  Buffer out = auto Buffer.new(0);
  return out.write_code_point(point);
}

// base64

/** Returns the bytes of `text` in standard base64, from RFC 4648 section
    4, with `=` padding.
*/
String String.base64_encode(String text) =>
  _base64(_STANDARD, (const unsigned char *) text, text.len());

/** Returns the bytes of `bytes` in standard base64 with `=` padding; each
    element contributes all of its bytes.
*/
String Block.base64_encode(Block bytes) =>
  _base64(_STANDARD, bytes.bytes, bytes.len() * bytes.width);

/** Returns the text that the padded standard base64 `text` encodes.
    Raises: `<malformed>` when `text` is not padded standard base64 or
    decodes to a NUL byte; `String.base64_decode_bytes` returns such bytes.
*/
String String.base64_decode(String text) {
  String operation = "String.base64_decode";
  Block bytes = auto _unbase64(_STANDARD, text, operation);
  return _text(bytes, operation);
}

/** Returns the bytes that the padded standard base64 `text` encodes, as a
    `Block` of 1-byte elements owned by the active `Scope`.
    Raises: `<malformed>` when `text` is not padded standard base64.
*/
Block String.base64_decode_bytes(String text) =>
  _unbase64(_STANDARD, text, "String.base64_decode_bytes");

/** Returns the bytes of `text` in the URL-safe base64 alphabet of RFC 4648
    section 5, which writes `-` and `_` for `+` and `/`, without padding.
*/
String String.base64url_encode(String text) =>
  _base64(_URL, (const unsigned char *) text, text.len());

/** Returns the bytes of `bytes` in URL-safe base64 without padding. */
String Block.base64url_encode(Block bytes) =>
  _base64(_URL, bytes.bytes, bytes.len() * bytes.width);

/** Returns the text that the URL-safe base64 `text` encodes; `=` padding
    is optional.
    Raises: `<malformed>` when `text` is not URL-safe base64 or decodes to
    a NUL byte.
*/
String String.base64url_decode(String text) {
  String operation = "String.base64url_decode";
  Block bytes = auto _unbase64(_URL, text, operation);
  return _text(bytes, operation);
}

/** Returns the bytes that the URL-safe base64 `text` encodes, as a `Block`
    of 1-byte elements owned by the active `Scope`.
    Raises: `<malformed>` when `text` is not URL-safe base64.
*/
Block String.base64url_decode_bytes(String text) =>
  _unbase64(_URL, text, "String.base64url_decode_bytes");

// hexadecimal

/** Returns the bytes of `text` in lowercase hexadecimal, two digits per
    byte.
*/
String String.hex_encode(String text) =>
  _hex((const unsigned char *) text, text.len());

/** Returns the bytes of `bytes` in lowercase hexadecimal; each element
    contributes all of its bytes.
*/
String Block.hex_encode(Block bytes) =>
  _hex(bytes.bytes, bytes.len() * bytes.width);

/** Returns the text that the hexadecimal `text` encodes, in digits of
    either case.
    Raises: `<malformed>` when `text` has an odd length or a character that
    is not a hexadecimal digit, or decodes to a NUL byte.
*/
String String.hex_decode(String text) {
  String operation = "String.hex_decode";
  Block bytes = auto _unhex(text, operation);
  return _text(bytes, operation);
}

/** Returns the bytes that the hexadecimal `text` encodes, as a `Block` of
    1-byte elements owned by the active `Scope`.
    Raises: `<malformed>` when `text` has an odd length or a character that
    is not a hexadecimal digit.
*/
Block String.hex_decode_bytes(String text) =>
  _unhex(text, "String.hex_decode_bytes");

// percent-encoding

/** Returns `text` with each byte outside the RFC 3986 unreserved set
    `A-Z a-z 0-9 - . _ ~` written as `%` and two uppercase hexadecimal
    digits, so the result can be one path segment, query name, or query
    value.
*/
String String.percent_encode(String text) {
  Buffer out = auto Buffer.new(0);
  for (const unsigned char *at = (const unsigned char *) text; at && *at;
       at++) {
    if (_unreserved(*at)) out.write_char(*at);
    else out.printf("%%%02X", *at);
  }
  return out;
}

/** Returns `text` with each `%` and the two hexadecimal digits after it
    replaced by the byte they name. Every other byte, `+` included, is
    kept.
    Raises: `<malformed>` for a `%` without two hexadecimal digits after
    it, or for `%00`.
*/
String String.percent_decode(String text) {
  if (!text || !strchr(text, '%')) return text;
  String operation = "String.percent_decode";
  Buffer out = auto Buffer.new(0);
  for (int i = 0; text[i] > 0; i++) {
    if (text[i] != '%') {
      out.write_char(text[i]);
      continue;
    }
    int byte = _byte_at(text, i + 1, operation);
    if (!byte) _malformed(operation, "NUL byte cannot appear in a String", i);
    out.write_char(byte);
    i += 2;
  }
  return out;
}

// decoding code points

/* Decodes the well-formed sequence of `length` bytes at `at`. */
static int _decode_point(const unsigned char *at, int length) {
  if (length == 1) return at[0];
  int point = at[0] & (0x7F >> length);
  for (int i = 1; i < length; i++) point = point << 6 | (at[i] & 0x3F);
  return point;
}

static void _malformed(String operation, String reason, int offset) {
  raise %(malformed (operation $operation) (reason $reason)
          (offset $offset));
}

static int _next_point(Iter iter, Var *out) {
  int cursor = iter.state, point;
  if (!String.try_next_code_point(iter.obj, cursor, point)) return 0;
  iter.state = cursor;
  *out = point;
  return 1;
}

// base64 groups

static String _base64(Alphabet a, const unsigned char *bytes, size_t count) {
  Buffer out = auto Buffer.new(0);
  for (size_t i = 0; i < count; i += 3) {
    size_t take = count - i < 3 ? count - i : 3;
    unsigned long group = (unsigned long) bytes[i] << 16;
    if (take > 1) group |= bytes[i + 1] << 8;
    if (take > 2) group |= bytes[i + 2];
    for (size_t j = 0; j <= take; j++)
      out.write_char(a.digits[group >> (18 - 6 * j) & 63]);
    if (a.pad) out.write_len("==", 3 - take);
  }
  return out;
}

/* Decodes each group of four characters into three bytes; a final group
   of two or three characters holds one or two. */
static Block _unbase64(Alphabet a, String text, String operation) {
  Block bytes = Block.new(1);
  const char *at = text;
  int length = _unpadded(a, text, operation);
  for (int i = 0; i < length; i += 4) {
    int take = length - i < 4 ? length - i : 4;
    if (take == 1) _malformed(operation, "incomplete group", i);
    unsigned long group = 0;
    for (int j = 0; j < 4; j++) {
      int digit = j < take ? _sextet(a, at[i + j]) : 0;
      if (digit < 0) _malformed(operation, "invalid character", i + j);
      group = group << 6 | digit;
    }
    unsigned char decoded[3] = {
      (unsigned char) (group >> 16), (unsigned char) (group >> 8),
      (unsigned char) group
    };
    bytes.append(decoded, take - 1);
  }
  return bytes;
}

/* The length of `text` before its padding. The standard alphabet requires
   padding; the URL alphabet accepts it when it completes the last group. */
static int _unpadded(Alphabet a, String text, String operation) {
  int length = text.len(), end = length;
  while (end > 0 && length - end < 2 && text[end - 1] == '=') end--;
  if ((end < length || a.pad) && length % 4)
    _malformed(operation, "padding must complete a group of four", length);
  return end;
}

static int _sextet(Alphabet a, int c) {
  if (c >= 'A' && c <= 'Z') return c - 'A';
  if (c >= 'a' && c <= 'z') return c - 'a' + 26;
  if (c >= '0' && c <= '9') return c - '0' + 52;
  if (c == a.digits[62]) return 62;
  return c == a.digits[63] ? 63 : -1;
}

/* The decoded `bytes` as a String, which cannot hold a NUL byte. */
static String _text(Block bytes, String operation) {
  const char *start = (const char *) bytes.bytes;
  const char *nul = memchr(start, 0, bytes.len());
  if (nul)
    raise %(malformed (operation $operation)
            (reason "NUL byte cannot appear in a String")
            (index $(nul - start)));
  return String.new_len(start, bytes.len());
}

// hexadecimal digits

static String _hex(const unsigned char *bytes, size_t count) {
  static const char digits[] = "0123456789abcdef";
  Buffer out = auto Buffer.new(0);
  for (size_t i = 0; i < count; i++) {
    out.write_char(digits[bytes[i] >> 4]);
    out.write_char(digits[bytes[i] & 15]);
  }
  return out;
}

static Block _unhex(String text, String operation) {
  int length = text.len();
  if (length % 2) _malformed(operation, "odd number of digits", length);
  Block bytes = Block.new(1);
  for (int i = 0; i < length; i += 2) {
    unsigned char byte = _byte_at(text, i, operation);
    bytes.push(&byte);
  }
  return bytes;
}

/* The byte that the two hexadecimal digits at `offset` spell. */
static int _byte_at(String text, int offset, String operation) {
  int high = _digit(text, offset, operation);
  int low = _digit(text, offset + 1, operation);
  return high << 4 | low;
}

static int _digit(String text, int offset, String operation) {
  int digit = scan_ascii_hex_value(text[offset]);
  if (digit < 0) _malformed(operation, "expected a hexadecimal digit", offset);
  return digit;
}

// unreserved bytes

static int _unreserved(int byte) =>
  (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z') ||
  scan_ascii_digit(byte) || (byte && strchr("-._~", byte));
