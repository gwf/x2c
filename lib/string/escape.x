/*  escape.x -- escaped spelling of canonical strings

    Copyright (c) 2025 Gary William Flake

    This module translates between a `String`'s bytes and their escaped
    spelling inside a C or x2c string literal: `escape`, `repr`, and
    `write_repr` write it, and `unescape`, `parse`, and `parse_char` read
    it. A changed result is built in a `String.malloc` buffer and finalized
    by `String.intern_free`, so the canonical header stays private to
    `string.x`.
*/

#include <limits.h>

#include "buffer.x"
#include "exception.x"
#include "scan.x"

Buffer Buffer.write_code_point(Buffer out, int point);

// writing escapes

/** Returns a canonical quoted and escaped representation of `str`.
    Empty input returns the canonical literal spelling `"\"\""`.
    Raises: the same causes as `String.escape`, or `<alloc-fail>` while
    formatting a nonempty `String`.
*/
String String.repr(String str) {
  if (!str) return "\"\"";
  return "\"%s\"".printf(str.escape());
}

/** Returns a canonical escaped representation of the bytes in `str`.
    Common control and delimiter bytes use named escapes, printable ASCII is
    copied, and every other byte uses a three-digit octal escape. `Null`
    input returns NULL.
    Raises: `<size-limit>` when the result cannot fit a `String`, or
    `<alloc-fail>` while constructing the result.
*/
meta native String String.escape(String str) {
  if (!str) return NULL;
  int bytes = 0;
  for (const char *at = str; *at; at++) {
    int width = _escape_byte((unsigned char) *at, NULL);
    if (bytes > INT_MAX - width - 1)
      raise %(size-limit (operation "String.escape"));
    bytes += width;
  }
  String string = String.malloc(bytes + 1), char *dst = string;
  for (const char *at = str; *at; at++)
    dst += _escape_byte((unsigned char) *at, dst);
  *dst = '\0';
  return string.intern_free();
}

/** Appends a quoted escaped representation of `str` to borrowed `out`.
    Bytes are streamed without first allocating an intermediate `String`. The
    same `out` is returned and not retained. Text written before a failure
    remains in the `Buffer`.
    Raises: any cause from `Buffer.write_char` or `Buffer.write_len`.
*/
Buffer String.write_repr(String str, Buffer out) {
  out.write_char('"');
  for (const char *at = str; at && *at; at++) {
    char escaped[4];
    int width = _escape_byte((unsigned char) *at, escaped);
    out.write_len(escaped, width);
  }
  return out.write_char('"');
}

// reading escapes

/** Parses one leading single-quoted escaped or literal byte, or returns -1.
    The opening quote, one decoded byte, and a closing quote are required.
    Text after that closing quote is ignored. A decoded NUL is returned as
    zero; malformed and null input returns -1, as does an octal escape above
    `\377`, which does not fit a byte.
*/
meta native int String.parse_char(String str) {
  if (!str) return -1;
  const char *at = str;
  if (*at++ != '\'' || !*at) return -1;
  int byte = *at++;
  if (byte == '\\') {
    if (!*at) return -1;
    int width = scan_c_escape_value((char *) at - 1, byte);
    if (width < 0 || byte < 0 || byte > 0377) return -1;
    at += width - 1;
  }
  return *at == '\'' ? byte : -1;
}

/** Returns the canonical unescaped contents of `str`.
    Matching outer `%"..."` or `"..."` delimiters are removed; unquoted input
    is unescaped directly. `Null` or empty input returns NULL. An unquoted
    input without backslashes is returned unchanged.
    Raises: `<alloc-fail>` while copying or decoding.
*/
meta native String String.parse(String str) {
  if (!str) return NULL;
  int n = str.len();
  if (str[0] == '%' && str[1] == '"' && str[n - 1] == '"')
    return x2c_string_unescape_bytes(String.new_len(str + 2, n - 3));
  if (str[0] == '"' && str[n - 1] == '"')
    return String.new_len(str + 1, n - 2).unescape();
  return str.unescape();
}

/** Decodes C backslash escapes in `str` into a canonical `String`.
    Hexadecimal escapes consume all following hex digits; universal escapes
    consume four digits after `u` or eight after `U` and encode UTF-8.
    Octal escapes consume at most three digits. Line continuations disappear.
    Null input returns NULL. Input without a backslash is canonicalized.
    Raises: `<bad-arg>` for a malformed escape or invalid Unicode point,
    or `<alloc-fail>` while constructing a changed result.
*/
meta native String String.unescape(String str) {
  if (!str || !("\\" in str)) return _canonical(str);
  Buffer out = auto Buffer.new(0);
  for (int i = 0, length = str.len(); i < length;) {
    int value = (unsigned char) str[i], width = 1;
    int universal = str[i] == '\\' &&
      (str[i + 1] == 'u' || str[i + 1] == 'U');
    if (str[i] == '\\') width = scan_c_escape_value(str + i, value);
    if (width < 0) raise %(bad-arg (operation "String.unescape"));
    i += width;
    if (value <= 0) continue;
    if (universal) out.write_code_point(value);
    else out.write_char((char) value);
  }
  return out;
}

/* Percent strings, quoted Atoms, and Lisp keep x2c's byte escapes. */
String x2c_string_unescape_bytes(String str) {
  int n = str.len();
  if (n == 0) return NULL;
  if (!("\\" in str)) return _canonical(str);
  String string = String.malloc(n + 1);
  if (_unescape_into(string, str) < 0) {
    string.free();
    raise %(bad-arg (operation "String.unescape"));
  }
  return string.intern_free();
}

/* Writes the escape of `ch` to `out` unless `out` is NULL, and returns its
   width: a named escape, the printable byte itself, or an octal escape. */
static inline int _escape_byte(unsigned char ch, char *out) {
  char letter = _escape_letter(ch);
  if (letter) {
    if (out) {
      out[0] = '\\';
      out[1] = letter;
    }
    return 2;
  }
  if (ch >= 32 && ch <= 126) {
    if (out) out[0] = ch;
    return 1;
  }
  if (out) {
    out[0] = '\\';
    out[1] = ((ch >> 6) & 0x03) + '0';
    out[2] = ((ch >> 3) & 0x07) + '0';
    out[3] = (ch & 0x07) + '0';
  }
  return 4;
}

/* The letter of the named escape for `ch`, or 0 when it has none. */
static inline char _escape_letter(unsigned char ch) {
  switch (ch) {
    case '\n': return 'n';
    case '\r': return 'r';
    case '\t': return 't';
    case '\b': return 'b';
    case '\f': return 'f';
    case '\v': return 'v';
    case '\\': return '\\';
    case '"':  return '"';
    case '\'': return '\'';
  }
  return 0;
}

/* Decodes the escape after a backslash and advances `at` past it. Returns
   its byte, a value above `\377` for an octal escape too large for a byte,
   or -1 for a backslash-newline, which stands for no byte. */
static inline int _decode_escape(const char *&at) {
  int esc = (unsigned char) *at++;
  switch (esc) {
    case 'x': case 'X': case 'u': case 'U': return _hex_escape(at, esc);
    case '0': case '1': case '2': case '3':
    case '4': case '5': case '6': case '7': return _octal_escape(at, esc);
    case '\n': return -1;
  }
  return _named_escape(esc);
}

/* Up to two hexadecimal digits; with none, the escape is its letter. */
static inline int _hex_escape(const char *&at, int esc) {
  int byte = 0, digits = 0;
  for (; *at && digits < 2; at++, digits++) {
    int hex = scan_ascii_hex_value(*at);
    if (hex < 0) break;
    byte = (byte << 4) | hex;
  }
  return digits ? byte : esc;
}

/* Up to three octal digits, the first of them `esc`. */
static inline int _octal_escape(const char *&at, int esc) {
  int byte = esc - '0';
  for (int digits = 1; *at && digits < 3; at++, digits++) {
    char next = *at;
    if (next < '0' || next > '7') break;
    byte = (byte << 3) | (next - '0');
  }
  return byte;
}

/* A letter escape's control byte. Every other escaped byte, such as `\\`,
   `\"`, or `\$`, stands for itself. */
static inline int _named_escape(int esc) {
  switch (esc) {
    case 'a': return '\a';
    case 'b': return '\b';
    case 'f': return '\f';
    case 'n': return '\n';
    case 'r': return '\r';
    case 't': return '\t';
    case 'v': return '\v';
  }
  return esc;
}

/* Decodes the escapes of `src` into `out`, NUL-terminated, and returns the
   bytes written, or -1 at an octal escape above `\377`. A trailing
   backslash is dropped. */
static int _unescape_into(char *out, const char *src) {
  char *dst = out;
  while (*src) {
    if (*src != '\\') {
      *dst++ = *src++;
      continue;
    }
    src++;
    if (!*src) break;
    int byte = _decode_escape(src);
    if (byte > 0377) return -1;
    if (byte > 0) *dst++ = byte;
  }
  *dst = '\0';
  return (int) (dst - out);
}
