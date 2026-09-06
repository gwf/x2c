/*  scan.x -- character-level token scanners for x2c

    Copyright (c) 2025 Gary William Flake

    Allocation-free scanners return a positive matched length, zero when
    their token class does not start at the input, and -1 for malformed input.
    Prefix-dispatched scanners report a missing required prefix through
    `Error`;
    that failure does not return.

    One forward-only typed scanner does all numeric scanning. Compatibility
    entry points retain their existing signatures without inspecting bytes
    before the supplied pointer. C literals use C escape widths and reject
    raw newlines; x2c percent strings and quoted symbols retain byte-oriented
    escapes and multiline behavior. Line comments and complete preprocessor
    lines may end at either newline or NUL, and a present newline is not part
    of the returned token.

    Inputs are borrowed only for a call and are never mutated. Except for the
    explicitly bounded helpers, they are NUL-terminated; every length is a byte
    count. Callers satisfy the stated opening-prefix preconditions.
*/

#pragma once

$(import "error-macros.xmacro")
$(import "private-keywords.xmacro")

#include "symbol.x"

/* Reports an ASCII letter without consulting the process locale. */
inline int scan_ascii_alpha(int c) => (unsigned) ((c | 32) - 'a') < 26;

/* Reports an ASCII decimal digit without consulting the process locale. */
inline int scan_ascii_digit(int c) => (unsigned) (c - '0') < 10;

#pragma private

#include <string.h>

static inline int _ascii_hex(int c) => scan_ascii_digit(c) ||
         (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');

static inline int _token_break(int c) => !((unsigned) (c - '0') < 10 ||
           (unsigned) ((c | 32) - 'a') < 26 || c == '_');

/* Classifies an already validated `n`-byte numeric token as integer or
   floating. A leading `+` is not skipped, so `e` or `E` in a plus-prefixed
   hexadecimal token is classified as a decimal exponent. The input is
   borrowed and need not end at `n`. */
Symbol scan_number_type(char *s, int n) {
  int i = n > 0 && s[0] == '-';
  int ishex = i + 1 < n && s[i] == '0' && (s[i+1] == 'x' || s[i+1] == 'X');
  while (i < n) {
    switch (s[i]) {
      case '.': case 'p': case 'P': return <float>;
      case 'e': case 'E': if (!ishex) return <float>;
        break;
    }
    i++;
  }
  return <int>;
}

/* Advances one-based `*l` and `*c` across `n` borrowed bytes.
   Each newline increments the line and resets the next byte to column one.
   `n` is nonnegative and all pointers are valid; columns count bytes. */
void scan_next_line_col(char *s, int n, int *l, int *c) {
  int line = *l, col = *c, char *next = s, *end = s + n, *newline;
  int found = 0;
  while (next < end && (newline = memchr(next, '\n', end - next))) {
    found = 1;
    line++;
    col = 1;
    next = newline + 1;
  }
  if (found) col += end - next;
  else col += n;
  *l = line; *c = col;
}

/* Returns the borrowed preprocessor-line byte count without its final newline.
   Backslash-LF and backslash-CRLF continuations remain in the token. A
   trailing backslash at NUL returns -1. The caller has recognized `#`. */
int scan_preprocessor(char *s) {
  int n = 0;
  while (s[n]) {
    if (s[n] == '\\' && s[n+1] == '\n') n += 2;
    else if (s[n] == '\\' && s[n+1] == '\r' && s[n+2] == '\n') n += 3;
    else if (s[n] == '\\' && !s[n+1]) return -1;
    else if (s[n] == '\n') return n;
    else n++;
  }
  return n;
}

/* Returns the leading C-whitespace byte count, zero for another first byte,
   and -1 for an empty input. */
int scan_white_space(char *s) {
  int n = 0;
  while (s[n])
    switch (s[n]) {
      case ' ': case '\t': case '\r': case '\v': case '\f': case '\n':
        n++; break;
      default: return n;
    }
  return (n > 0) ? n : -1;
}

/* Returns a `//` comment's bytes without its final newline, or through NUL.
   Raises: `<bad-arg>` for NULL or a non-comment prefix. */
int scan_line_comment(char *s) {
  if (!s || s[0] != '/' || s[1] != '/')
    raise %(bad-arg (owner "scan_line_comment"));
  int n = 2;
  while (s[n]) {
    if (s[n] == '\n') return n;
    n++;
  }
  return n;
}

/* Returns a complete block comment's byte count, or -1 when NUL arrives
   first. `status`, when nonnull, receives `<ok>` or `<incomplete>`. Raises:
   `<bad-arg>` for NULL or a non-comment prefix. */
int scan_block_comment_status(char *s, Symbol *status) {
  if (!s || s[0] != '/' || s[1] != '*')
    raise %(bad-arg (owner "scan_block_comment_status"));
  if (status) *status = <ok>;
  int n = 2;
  while (s[n]) {
    if (s[n] == '*' && s[n+1] == '/') return n+2;
    n++;
  }
  if (status) *status = <incomplete>;
  return -1;
}

/* Returns the same length as `scan_block_comment_status` without a status. */
int scan_block_comment(char *s) => scan_block_comment_status(s, NULL);

/* Returns an ASCII C identifier's byte count. Raises: `<bad-arg>` for NULL
   or a non-identifier start. */
int scan_identifier(char *s) {
  if (!s || (!scan_ascii_alpha((unsigned char) s[0]) && s[0] != '_'))
    raise %(bad-arg (owner "scan_identifier"));
  int n = 1;
  while ((unsigned) ((unsigned char) s[n] - '0') < 10 ||
         (unsigned) (((unsigned char) s[n] | 32) - 'a') < 26 ||
         s[n] == '_')
    n++;
  return n;
}

/* Returns the keyword Symbol for exactly `n` borrowed bytes, or zero.
   The C spellings `thread_local` and `_Thread_local` normalize to `threaded`;
   matching is otherwise case-sensitive. */
Symbol scan_keyword_type(const char *s, int n) {
  if (!s) return 0;
  switch (n) {
    case 2: if (!memcmp(s, "do", 2)) return <do>;
      if (!memcmp(s, "if", 2)) return <if>;
      if (!memcmp(s, "in", 2)) return <in>;
      break;
    case 3: if (!memcmp(s, "for", 3)) return <for>;
      if (!memcmp(s, "int", 3)) return <int>;
      if (!memcmp(s, "try", 3)) return <try>;
      break;
    case 4: if (!memcmp(s, "auto", 4)) return <auto>;
      if (!memcmp(s, "case", 4)) return <case>;
      if (!memcmp(s, "char", 4)) return <char>;
      if (!memcmp(s, "else", 4)) return <else>;
      if (!memcmp(s, "enum", 4)) return <enum>;
      if (!memcmp(s, "goto", 4)) return <goto>;
      if (!memcmp(s, "long", 4)) return <long>;
      if (!memcmp(s, "void", 4)) return <void>;
      break;
    case 5: if (!memcmp(s, "break", 5)) return <break>;
      if (!memcmp(s, "catch", 5)) return <catch>;
      if (!memcmp(s, "const", 5)) return <const>;
      if (!memcmp(s, "defer", 5)) return <defer>;
      if (!memcmp(s, "float", 5)) return <float>;
      if (!memcmp(s, "match", 5)) return <match>;
      if (!memcmp(s, "raise", 5)) return <raise>;
      if (!memcmp(s, "short", 5)) return <short>;
      if (!memcmp(s, "union", 5)) return <union>;
      if (!memcmp(s, "while", 5)) return <while>;
      break;
    case 6: if (!memcmp(s, "double", 6)) return <double>;
      if (!memcmp(s, "extern", 6)) return <extern>;
      if (!memcmp(s, "import", 6)) return <import>;
      if (!memcmp(s, "inline", 6)) return <inline>;
      if (!memcmp(s, "return", 6)) return <return>;
      if (!memcmp(s, "signed", 6)) return <signed>;
      if (!memcmp(s, "sizeof", 6)) return <sizeof>;
      if (!memcmp(s, "static", 6)) return <static>;
      if (!memcmp(s, "struct", 6)) return <struct>;
      if (!memcmp(s, "switch", 6)) return <switch>;
      break;
    case 7: if (!memcmp(s, "default", 7)) return <default>;
      if (!memcmp(s, "finally", 7)) return <finally>;
      if (!memcmp(s, "typedef", 7)) return <typedef>;
      break;
    case 8: if (!memcmp(s, "delegate", 8)) return <delegate>;
      if (!memcmp(s, "protocol", 8)) return <protocol>;
      if (!memcmp(s, "continue", 8)) return <continue>;
      if (!memcmp(s, "register", 8)) return <register>;
      if (!memcmp(s, "restrict", 8)) return <restrict>;
      if (!memcmp(s, "threaded", 8)) return <threaded>;
      if (!memcmp(s, "unsigned", 8)) return <unsigned>;
      if (!memcmp(s, "volatile", 8)) return <volatile>;
      break;
    case 10: if (!memcmp(s, "associated", 10)) return <associated>;
      break;
    /* C spells thread-local storage two other ways. Both mean `threaded`,
       so C that already uses either passes through unchanged. */
    case 12: if (!memcmp(s, "thread_local", 12)) return <threaded>;
      break;
    case 13: if (!memcmp(s, "_Thread_local", 13)) return <threaded>;
      break;
  }
  return 0;
}

/* Returns a keyword identifier's byte count or -1 for another identifier.
   Raises: `<bad-arg>` when `s` does not begin an identifier. */
int scan_keyword(char *s) {
  int n = scan_identifier(s);
  return scan_keyword_type(s, n) ? n : -1;
}

/* Returns the longest supported C or x2c operator prefix, or -1.
   The caller supplies a nonnull NUL-terminated input. */
int scan_c_operator(char *s) {
  switch (*s) {
    case '.':  // ..., .
      return (s[1] == '.' && s[2] == '.') ? 3 : 1;
    case '>': // >>=, >>, >=, >
      return (s[1] == '>') ? ((s[2] == '=') ? 3 : 2) : (s[1] == '=') ? 2 : 1;
    case '<': // <<=, <<, <=, <
      return (s[1] == '<') ? ((s[2] == '=') ? 3 : 2) : (s[1] == '=') ? 2 : 1;
    case '+': // +=, ++, +
      return (s[1] == '=') ? 2 : (s[1] == '+') ? 2 : 1;
    case '-': // -=, --, ->
      return (s[1] == '=') ? 2 : (s[1] == '-') ? 2 : (s[1] == '>') ? 2 : 1;
    case '*': // *=, *
      return (s[1] == '=') ? 2 : 1;
    case '/': // /=, /
      return (s[1] == '=') ? 2 : 1;
    case '%': // %=, %
      return (s[1] == '=') ? 2 : 1;
    case '&': // &=, &&
      return (s[1] == '=') ? 2 : (s[1] == '&') ? 2 : 1;
    case '^': // ^=, ^
      return (s[1] == '=') ? 2 : 1;
    case '|': // |=, ||
      return (s[1] == '=') ? 2 : (s[1] == '|') ? 2 : 1;
    case '=': // ===, ==, =
      return (s[1] == '=') ? ((s[2] == '=') ? 3 : 2) : 1;
    case '!': // !==, !=, !
      return (s[1] == '=') ? ((s[2] == '=') ? 3 : 2) : 1;
    // ~, ;, , :, (, ), [, ], {, }, ?, @
    case '~': case ';': case ',': case ':': case '(': case ')':
    case '[': case ']': case '{': case '}': case '?': case '@':
      return 1;
    default: return -1;
  }
}

/* Scans x2c byte escapes and classifies truncation separately. */
static int _escape_sequence_status(char *s, Symbol *status) {
  int n = 1;
  if (!s[n]) {
    if (status) *status = <incomplete>;
    return -1;
  }
  switch (s[n]) {
    case 'a': case 'b': case 'f': case 'n': case 'r': case 't': case 'v':
    case '\n': case '\'': case '"': case '?': case '\\':
      return n + 1;
    case '\r':
      if (!s[n + 1]) {
        if (status) *status = <incomplete>;
        return -1;
      }
      if (s[n + 1] == '\n') return n + 2;
      break;
    case 'x': case 'X': case 'u': case 'U': n++;
      int start = n;
      if (!s[n]) {
        if (status) *status = <incomplete>;
        return -1;
      }
      if (_ascii_hex((unsigned char) s[n])) n++;
      if (_ascii_hex((unsigned char) s[n])) n++;
      if (n == start) break;
      return n;
    case '0': case '1': case '2': case '3': case '4': case '5':
    case '6': case '7':
      n++;
      if (s[n] >= '0' && s[n] <= '7') n++;
      if (s[n] >= '0' && s[n] <= '7') n++;
      return n;
  }
  if (status) *status = <malformed>;
  return -1;
}

/* Returns one x2c byte-oriented escape's length or -1 for malformed or
   truncated input. The caller has already recognized the backslash. */
int scan_escape_sequence(char *s) => _escape_sequence_status(s, NULL);

/* Scans a C escape and classifies truncation separately. */
static int _c_escape_sequence_status(char *s, Symbol *status) {
  int n = 1;
  if (!s[n]) {
    if (status) *status = <incomplete>;
    return -1;
  }
  switch (s[n]) {
    case 'a': case 'b': case 'f': case 'n': case 'r': case 't': case 'v':
    case '\n': case '\'': case '"': case '?': case '\\':
      return n + 1;
    case '\r':
      if (!s[n + 1]) {
        if (status) *status = <incomplete>;
        return -1;
      }
      if (s[n + 1] == '\n') return n + 2;
      break;
    case '0': case '1': case '2': case '3': case '4': case '5':
    case '6': case '7':
      n++;
      if (s[n] >= '0' && s[n] <= '7') n++;
      if (s[n] >= '0' && s[n] <= '7') n++;
      return n;
    case 'x': case 'X': n++;
      if (!s[n]) {
        if (status) *status = <incomplete>;
        return -1;
      }
      if (!_ascii_hex((unsigned char) s[n])) break;
      while (_ascii_hex((unsigned char) s[n])) n++;
      return n;
    case 'u': n++;
      for (int i = 0; i < 4; i++) {
        if (!s[n]) {
          if (status) *status = <incomplete>;
          return -1;
        }
        if (!_ascii_hex((unsigned char) s[n++])) goto malformed;
      }
      return n;
    case 'U': n++;
      for (int i = 0; i < 8; i++) {
        if (!s[n]) {
          if (status) *status = <incomplete>;
          return -1;
        }
        if (!_ascii_hex((unsigned char) s[n++])) goto malformed;
      }
      return n;
  }
malformed: if (status) *status = <malformed>;
  return -1;
}

/* Used by C character literals and legacy string callers. */
static int _c_escape_sequence(char *s) => _c_escape_sequence_status(s, NULL);

/* Returns a C String literal's complete byte count, or -1 on malformed or
   truncated input. The caller supplies the opening quote. `status`, when
   nonnull, distinguishes `<malformed>` from `<incomplete>`. */
int scan_c_string_status(char *s, Symbol *status) {
  if (status) *status = <ok>;
  int m, n = 1;
  while (s[n]) {
    if (s[n] == '\\') {
      if ((m = _c_escape_sequence_status(s + n, status)) < 0) return -1;
      n += m;
    }
    else if (s[n] == '"') return n + 1;
    else if (s[n] == '\n' || s[n] == '\r') {
      if (status) *status = <malformed>;
      return -1;
    }
    else n++;
  }
  if (status) *status = <incomplete>;
  return -1;
}

/* Returns the same result as `scan_c_string_status` without a status. */
int scan_c_string(char *s) => scan_c_string_status(s, NULL);

/* Returns one complete C character literal's byte count, or -1.
   The caller supplies the opening quote; raw newlines and empty or multi-byte
   unescaped contents are malformed. */
int scan_c_character(char *s) {
  int m, n = 1;
  if (s[n] == '\\') {
    if ((m = _c_escape_sequence(s + n)) < 0) return -1;
    n += m;
  }
  else {
    if (!s[n] || s[n] == '\n' || s[n] == '\r' || s[n] == '\'') return -1;
    n++;
  }
  return s[n] == '\'' ? n + 1 : -1;
}

/* Precondition: the integer digits have already been scanned. */
static int _int_suffix(char *s) {
  int n = 0;
  switch (s[n]) {
    case 'u': case 'U':  n++;
      switch (s[n]) {
        case 'l': case 'L':  n++;
          switch (s[n]) {
            case 'l': case 'L':  n++; break;
            default: break;
          }
          break;
        default: break;
      }
      break;
    case 'l': case 'L': n++;
      switch (s[n]) {
        case 'l': case 'L': n++;
          switch (s[n]) {
            case 'u': case 'U': n++; break;
            default: break;
          }
          break;
        case 'u': case 'U': n++; break;
        default: break;
      }
      break;
    default: break;
  }
  if (!_token_break(s[n])) return -1;
  return n;
}

/* Precondition: the floating digits have already been scanned. */
static int _float_suffix(char *s) {
  int n = 0;
  switch (s[n]) {
    case 'f': case 'F': case 'l': case 'L': n++; break;
  }
  if (!_token_break(s[n])) return -1;
  return n;
}

static int _digits(char *s, int base) {
  int n = 0;
  loop {
    int c = (unsigned char) s[n];
    unsigned digit = (unsigned) (c - '0');
    int valid = digit < 10 && digit < (unsigned) base;
    if (base == 16)
      valid = valid || (c >= 'a' && c <= 'f') ||
              (c >= 'A' && c <= 'F');
    if (!valid) return n;
    n++;
  }
}

static int _exponent(char *s) {
  int n = 0;
  if (s[n] == '+' || s[n] == '-') n++;
  int digits = _digits(s + n, 10);
  if (!digits) return -1;
  n += digits;
  int suffix = _float_suffix(s + n);
  return suffix < 0 ? -1 : n + suffix;
}

/* `digit_before` says a digit was consumed before the decimal point, which
   is what scan_float promises its callers. */
static int _float_tail(char *s, int digit_before) {
  int n = _digits(s, 10);
  if (!digit_before && !n) return -1;
  if (s[n] == 'e' || s[n] == 'E') {
    int exponent = _exponent(s + n + 1);
    return exponent < 0 ? -1 : n + 1 + exponent;
  }
  int suffix = _float_suffix(s + n);
  return suffix < 0 ? -1 : n + suffix;
}

/* Returns the numeric-tail length after a decimal point already consumed
   following at least one digit, or -1 for a malformed tail. */
int scan_float(char *s) => _float_tail(s, 1);

/* Returns the hexadecimal exponent tail after an already consumed `p` or `P`,
   or -1 when the required decimal exponent is malformed. */
int scan_hexponent(char *s) => _exponent(s);

static int _radix_integer(char *s, int base, int digit_before) {
  int n = _digits(s, base);
  if (!digit_before && !n) return -1;
  int suffix = _int_suffix(s + n);
  return suffix < 0 ? -1 : n + suffix;
}

static int _hex_number(char *s, Symbol *type) {
  int n = 0;
  while ((unsigned) ((unsigned char) s[n] - '0') < 10 ||
         (unsigned) (((unsigned char) s[n] | 32) - 'a') < 6)
    n++;
  int digits = n, has_point = 0;
  if (s[n] == '.') {
    has_point = 1;
    n++;
    int fraction = _digits(s + n, 16);
    digits += fraction;
    n += fraction;
  }
  if (!digits) return -1;
  if (s[n] == 'p' || s[n] == 'P') {
    int exponent = _exponent(s + n + 1);
    if (exponent < 0) return -1;
    if (type) *type = <float>;
    return n + 1 + exponent;
  }
  if (has_point) return -1;
  int suffix = _int_suffix(s + n);
  if (suffix < 0) return -1;
  if (type) *type = <int>;
  return n + suffix;
}

static int _decimal_number(char *s, Symbol *type) {
  int n = 0;
  while ((unsigned) ((unsigned char) s[n] - '0') < 10) n++;
  if (s[n] == '.') {
    int fraction = _float_tail(s + n + 1, n > 0);
    if (fraction < 0) return -1;
    if (type) *type = <float>;
    return n + 1 + fraction;
  }
  if (!n) return 0;
  if (s[n] == 'e' || s[n] == 'E') {
    int exponent = _exponent(s + n + 1);
    if (exponent < 0) return -1;
    if (type) *type = <float>;
    return n + 1 + exponent;
  }
  int suffix = _int_suffix(s + n);
  if (suffix < 0) return -1;
  if (type) *type = <int>;
  return n + suffix;
}

/* Scans an unsigned decimal integer or floating spelling.
   Returns its byte count, zero when no number starts here, or -1 when a
   numeric prefix has a malformed continuation. */
int scan_digital(char *s) => _decimal_number(s, NULL);

/* Scans a signed or unsigned C/x2c numeric token from borrowed NUL-terminated
   input. Returns a positive byte count, zero when no number starts here, or -1
   for a malformed numeric prefix. On success a nonnull `type` receives `<int>`
   or `<float>`; otherwise it is unchanged. */
int scan_number_typed(char *s, Symbol *type) {
  if (!s) return 0;
  int sign = s[0] == '-' || s[0] == '+', char *number = s + sign, int n;
  Symbol found = <int>;
  if (number[0] == '0') {
    switch (number[1]) {
      case 'x': case 'X': n = _hex_number(number + 2, &found);
        if (n < 0) return -1;
        n += 2;
        break;
      case 'b': case 'B': n = _radix_integer(number + 2, 2, 0);
        if (n < 0) return -1;
        n += 2;
        break;
      case 'o': case 'O': n = _radix_integer(number + 2, 8, 0);
        if (n < 0) return -1;
        n += 2;
        break;
      case '1': case '2': case '3': case '4': case '5':
      case '6': case '7':
        n = _radix_integer(number + 2, 8, 1);
        if (n < 0) return -1;
        n += 2;
        break;
      default: n = _decimal_number(number, &found);
        break;
    }
  }
  else n = _decimal_number(number, &found);
  if (n <= 0) return sign ? 0 : n;
  if (type) *type = found;
  return sign + n;
}

/* Returns the same result as `scan_number_typed` without its type. */
int scan_number(char *s) => scan_number_typed(s, NULL);

/* Percent strings differ from C strings:

   - embedded newlines are literal bytes;
   - backslash-newline and backslash-CRLF continue the source line;
   - `$` must be escaped or doubled unless it starts interpolation;
   - `$name` and `${expression}` begin interpolation.

   The caller has consumed the opening `%"`; `s[0]` is neither `$` nor the
   closing quote. Returns the bytes before the next interpolation or closing
   quote, excluding that delimiter, or -1 for a malformed escape or NUL before
   either delimiter.
*/
int scan_string_segment(char *s) {
  int n = 0;
  while (s[n]) {
    if (s[n] == '\\') {
      if (s[n+1] == '$') n += 2;
      else {
        int m = scan_escape_sequence(s + n);
        if (m < 0) return -1;
        n += m;
      }
    }
    else if (s[n] == '$' && s[n+1] == '$') n += 2;
    else if (s[n] == '$' || s[n] == '"') return n;
    else n++;
  }
  return -1;
}

/* One atom spelling for Lisp source and `%(...)` list literals. Reader
   punctuation, the x2c escape openers, whitespace, and a comment opener end
   it; a backslash escapes the next byte. Returns zero when no atom starts and
   -1 only for a trailing backslash. `status`, when nonnull, receives `<ok>` or
   `<incomplete>`. */
int scan_atom_status(char *s, Symbol *status) {
  if (status) *status = <ok>;
  if (!s || !*s || strchr("()'`,\"$@{[", *s)) return 0;
  if (s[0] == '\\' && !s[1]) {
    if (status) *status = <incomplete>;
    return -1;
  }
  int n = 1;
  while (s[n]) {
    if (strchr("()'`,\"$@{[", s[n]) || strchr(" \n\t\v\f\r", s[n])) return n;
    if (s[n] == '/' && (s[n + 1] == '/' || s[n + 1] == '*')) return n;
    if (s[n] == '\\') {
      if (!s[n + 1]) {
        if (status) *status = <incomplete>;
        return -1;
      }
      n += 2;
    }
    else n++;
  }
  return n;
}

/* Returns the same result as `scan_atom_status` without a status. */
int scan_atom(char *s) => scan_atom_status(s, NULL);

/* Scans a quoted Symbol spelling from its opening quote through its closing
   quote, using x2c byte escapes. A raw newline is ordinary text. */
static int _quoted_symbol_status(char *s, Symbol *status) {
  int n = 1;
  while (s[n]) {
    if (s[n] == '\\') {
      int m = _escape_sequence_status(s + n, status);
      if (m < 0) return -1;
      n += m;
    }
    else if (s[n] == '"') return n + 1;
    else n++;
  }
  if (status) *status = <incomplete>;
  return -1;
}

/* One atom spelling inside `%<<...>>`. A leading quote reads the quoted
   spelling of `<"...">` without its angle brackets, so `>>` inside the quotes
   belongs to the atom. Otherwise it shares only whitespace, `$`, `@` and the
   backslash escape with scan_atom: reader punctuation and comment openers are
   ordinary bytes here, `>>` ends the atom, and the spelling may be empty
   because the caller has not ruled the first byte out. Returns -1 for a
   malformed quoted spelling or trailing backslash. */
int scan_symbol_set_atom(char *s) {
  if (!s || !*s) return 0;
  if (s[0] == '"') return _quoted_symbol_status(s, NULL);
  int n = 0;
  while (s[n]) {
    if (s[n] == '>' && s[n + 1] == '>') break;
    if (strchr(" \n\t\v\f\r$@", s[n])) break;
    if (s[n] == '\\') {
      if (!s[n + 1]) return -1;
      n += 2;
    }
    else n++;
  }
  return n;
}

/* Scans `<simple>` or `<"...">` from borrowed NUL-terminated input.
   Returns zero without an opening angle, a positive byte count on success, or
   -1. `status`, when nonnull, distinguishes `<incomplete>` from `<malformed>`;
   the input must be nonnull. */
int scan_symbol_literal_status(char *s, Symbol *status) {
  if (status) *status = <ok>;
  if (s[0] != '<') return 0;
  int n = 1;
  if (s[n] == '"') {
    int m = _quoted_symbol_status(s + n, status);
    if (m < 0) return -1;
    n += m;
    if (s[n] == '>') return n + 1;
    if (status) *status = s[n] ? <malformed> : <incomplete>;
    return -1;
  }
  int start = n;
  while (s[n]) {
    if (s[n] == '>') {
      if (n > start) return n + 1;
      if (status) *status = <malformed>;
      return -1;
    }
    if (s[n] == ' ' || s[n] == '\t' || s[n] == '\r' || s[n] == '\n' ||
        s[n] == '\v' || s[n] == '\f') {
      if (status) *status = <malformed>;
      return -1;
    }
    n++;
  }
  if (status) *status = <incomplete>;
  return -1;
}

/* Returns the same result as `scan_symbol_literal_status` without a status. */
int scan_symbol_literal(char *s) => scan_symbol_literal_status(s, NULL);
