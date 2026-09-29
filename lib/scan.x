/*  scan.x -- character-level token scanners for x2c

    Copyright (c) 2025 Gary William Flake

    Allocation-free scanners return a positive matched length, zero when
    their token class does not start at the input, and -1 for malformed input.
    Prefix-dispatched scanners report a missing required prefix through
    `Error`; that failure does not return.

    Inputs are borrowed only for a call and are never mutated. Except for the
    explicitly bounded helpers, they are NUL-terminated; every length is a byte
    count. Callers satisfy the stated opening-prefix preconditions.
*/

#pragma once

$(import "error-macros.xmacro")

#include "symbol.x"

/* Reports an ASCII letter without consulting the process locale. */
inline int scan_ascii_alpha(int c) => (unsigned) ((c | 32) - 'a') < 26;

/* Reports an ASCII decimal digit without consulting the process locale. */
inline int scan_ascii_digit(int c) => (unsigned) (c - '0') < 10;

#pragma private

#include <string.h>

static inline int _ascii_hex(int c) =>
  scan_ascii_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');

static inline int _token_break(int c) =>
  !(scan_ascii_digit(c) || scan_ascii_alpha(c) || c == '_');

/* Reports `why` through a nonnull `status` and returns -1. */
static inline int _fail(Symbol *status, Symbol why) {
  if (status) *status = why;
  return -1;
}

/* white space and comments

   Line comments and complete preprocessor lines may end at either newline
   or NUL, and a present newline is not part of the returned token. */

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
  return n > 0 ? n : -1;
}

/* Returns a `//` comment's bytes without its final newline, or through NUL.
   Raises: `<bad-arg>` for NULL or a non-comment prefix. */
int scan_line_comment(char *s) {
  if (!s || s[0] != '/' || s[1] != '/')
    raise %(bad-arg (owner "scan_line_comment"));
  int n = 2;
  while (s[n] && s[n] != '\n') n++;
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
    if (s[n] == '*' && s[n + 1] == '/') return n + 2;
    n++;
  }
  return _fail(status, <incomplete>);
}

/* Returns the same length as `scan_block_comment_status` without a status. */
int scan_block_comment(char *s) => scan_block_comment_status(s, NULL);

/* Returns the borrowed preprocessor-line byte count without its final newline.
   Backslash-LF and backslash-CRLF continuations remain in the token. A
   trailing backslash at NUL returns -1. The caller has recognized `#`. */
int scan_preprocessor(char *s) {
  int n = 0;
  while (s[n]) {
    if (s[n] == '\\' && s[n + 1] == '\n') n += 2;
    else if (s[n] == '\\' && s[n + 1] == '\r' && s[n + 2] == '\n') n += 3;
    else if (s[n] == '\\' && !s[n + 1]) return -1;
    else if (s[n] == '\n') return n;
    else n++;
  }
  return n;
}

/* numbers

   One forward-only typed scanner does all numeric scanning. Its entry
   points never inspect bytes before the supplied pointer. */

/* Scans a signed or unsigned C/x2c numeric token from borrowed NUL-terminated
   input. Returns a positive byte count, zero when no number starts here, or -1
   for a malformed numeric prefix. On success a nonnull `type` receives `<int>`
   or `<float>`; otherwise it is unchanged. */
int scan_number_typed(char *s, Symbol *type) {
  if (!s) return 0;
  int sign = s[0] == '-' || s[0] == '+', char *number = s + sign;
  Symbol found = <int>;
  int n = _prefixed_number(number, &found);
  if (n < 0) return -1;
  if (!n) n = _decimal_number(number, &found);
  if (n <= 0) return sign ? 0 : n;
  if (type) *type = found;
  return sign + n;
}

/* Returns the same result as `scan_number_typed` without its type. */
int scan_number(char *s) => scan_number_typed(s, NULL);

/* Scans a hexadecimal, binary, or octal number with its `0` prefix, and
   returns its length, -1 when it is malformed, or zero for another spelling.
   As in C, a point or exponent makes octal-looking digits decimal floating. */
static int _prefixed_number(char *s, Symbol *type) {
  if (s[0] != '0') return 0;
  int n;
  switch (s[1]) {
    case 'x': case 'X': n = _hex_number(s + 2, type); break;
    case 'b': case 'B': n = _radix_integer(s + 2, 2, 0); break;
    case 'o': case 'O': n = _radix_integer(s + 2, 8, 0); break;
    case '1': case '2': case '3': case '4': case '5': case '6': case '7': {
      char after = s[_digits(s, 10)];
      if (after == '.' || after == 'e' || after == 'E') return 0;
      n = _radix_integer(s + 2, 8, 1);
      break;
    }
    default: return 0;
  }
  return n < 0 ? -1 : n + 2;
}

/* Hexadecimal digits with an optional fraction. A `p` exponent makes the
   number floating, and a fraction requires one. */
static int _hex_number(char *s, Symbol *type) {
  int n = _digits(s, 16), digits = n, point = s[n] == '.';
  if (point) {
    int fraction = _digits(s + n + 1, 16);
    digits += fraction;
    n += 1 + fraction;
  }
  if (!digits) return -1;
  if (s[n] == 'p' || s[n] == 'P') return _exponent_tail(s, n, type);
  if (point) return -1;
  return _integer_tail(s, n, type);
}

/* Decimal digits, then a fraction, an exponent, or an integer suffix. */
static int _decimal_number(char *s, Symbol *type) {
  int n = _digits(s, 10);
  if (s[n] == '.') {
    int fraction = _float_tail(s + n + 1, n > 0);
    if (fraction < 0) return -1;
    if (type) *type = <float>;
    return n + 1 + fraction;
  }
  if (!n) return 0;
  if (s[n] == 'e' || s[n] == 'E') return _exponent_tail(s, n, type);
  return _integer_tail(s, n, type);
}

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

/* Scans an unsigned decimal integer or floating spelling.
   Returns its byte count, zero when no number starts here, or -1 when a
   numeric prefix has a malformed continuation. */
int scan_digital(char *s) => _decimal_number(s, NULL);

/* Returns the numeric-tail length after a decimal point already consumed
   following at least one digit, or -1 for a malformed tail. */
int scan_float(char *s) => _float_tail(s, 1);

/* Returns the hexadecimal exponent tail after an already consumed `p` or `P`,
   or -1 when the required decimal exponent is malformed. */
int scan_hexponent(char *s) => _exponent(s);

// digits, exponents, and suffixes

static int _digits(char *s, int base) {
  int n = 0;
  while (_digit((unsigned char) s[n], base)) n++;
  return n;
}

static inline int _digit(int c, int base) =>
  base == 16 ? _ascii_hex(c) : (unsigned) (c - '0') < (unsigned) base;

/* An exponent after the mantissa's `n` bytes makes a number floating. */
static int _exponent_tail(char *s, int n, Symbol *type) {
  int exponent = _exponent(s + n + 1);
  if (exponent < 0) return -1;
  if (type) *type = <float>;
  return n + 1 + exponent;
}

static int _integer_tail(char *s, int n, Symbol *type) {
  int suffix = _int_suffix(s + n);
  if (suffix < 0) return -1;
  if (type) *type = <int>;
  return n + suffix;
}

static int _radix_integer(char *s, int base, int digit_before) {
  int n = _digits(s, base);
  if (!digit_before && !n) return -1;
  return _integer_tail(s, n, NULL);
}

/* `digit_before` says a digit was consumed before the decimal point, which
   is what scan_float promises its callers. */
static int _float_tail(char *s, int digit_before) {
  int n = _digits(s, 10);
  if (!digit_before && !n) return -1;
  if (s[n] == 'e' || s[n] == 'E') return _exponent_tail(s, n, NULL);
  int suffix = _float_suffix(s + n);
  return suffix < 0 ? -1 : n + suffix;
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

/* Precondition: the integer digits have already been scanned. The suffix
   is `u` with up to two `l`s after it, or one or two `l`s with an optional
   `u` after them, each letter in either case. */
static int _int_suffix(char *s) {
  int n = 0;
  if (_is_u(s[0])) n = 1 + _longs(s + 1);
  else if (_is_l(s[0])) {
    n = _longs(s);
    if (_is_u(s[n])) n++;
  }
  return _token_break(s[n]) ? n : -1;
}

/* The length of an `l` or `ll` at `s`, or zero. */
static int _longs(char *s) {
  if (!_is_l(s[0])) return 0;
  return _is_l(s[1]) ? 2 : 1;
}

static inline int _is_l(int c) => c == 'l' || c == 'L';
static inline int _is_u(int c) => c == 'u' || c == 'U';

/* Precondition: the floating digits have already been scanned. */
static int _float_suffix(char *s) {
  int n = 0;
  switch (s[n]) {
    case 'f': case 'F': case 'l': case 'L': n++; break;
  }
  return _token_break(s[n]) ? n : -1;
}

// identifiers, keywords, and operators

/* Returns an ASCII C identifier's byte count. Raises: `<bad-arg>` for NULL
   or a non-identifier start. */
int scan_identifier(char *s) {
  if (!s || (!scan_ascii_alpha((unsigned char) s[0]) && s[0] != '_'))
    raise %(bad-arg (owner "scan_identifier"));
  int n = 1;
  while (!_token_break((unsigned char) s[n])) n++;
  return n;
}

/* Returns a keyword identifier's byte count or -1 for another identifier.
   Raises: `<bad-arg>` when `s` does not begin an identifier. */
int scan_keyword(char *s) {
  int n = scan_identifier(s);
  return scan_keyword_type(s, n) ? n : -1;
}

/* Returns the keyword Symbol for exactly `n` borrowed bytes, or zero.
   The C spellings `thread_local` and `_Thread_local` normalize to `threaded`;
   matching is otherwise case-sensitive. */
Symbol scan_keyword_type(const char *s, int n) {
  if (!s) return 0;
  switch (n) {
    case 2:  return _keyword(s, 2, keywords2);
    case 3:  return _keyword(s, 3, keywords3);
    case 4:  return _keyword(s, 4, keywords4);
    case 5:  return _keyword(s, 5, keywords5);
    case 6:  return _keyword(s, 6, keywords6);
    case 7:  return _keyword(s, 7, keywords7);
    case 8:  return _keyword(s, 8, keywords8);
    case 10: return _keyword(s, 10, keywords10);
    case 12: return _keyword(s, 12, keywords12);
    case 13: return _keyword(s, 13, keywords13);
  }
  return 0;
}

typedef struct _Keyword { const char *text, Symbol type; } _Keyword;

/* Returns the type of the first row whose `n`-byte spelling matches `s`, or
   zero. A constant `n` lets the C compiler compare each spelling inline. */
static inline Symbol _keyword(const char *s, int n, const _Keyword *rows) {
  for (; rows.text; rows++) if (!memcmp(s, rows.text, n)) return rows.type;
  return 0;
}

/* Keyword spellings by length, in the order a lookup tries them. GNU C
   spells `inline` and `restrict` with underscores, and C spells
   thread-local storage two other ways. Each means the standard keyword, so
   C that already uses any of them passes through unchanged. */
static const _Keyword keywords2[] = {
  {"do", <do>}, {"if", <if>}, {"in", <in>}, {NULL}};
static const _Keyword keywords3[] = {
  {"for", <for>}, {"int", <int>}, {"try", <try>}, {NULL}};
static const _Keyword keywords4[] = {
  {"auto", <auto>}, {"case", <case>}, {"char", <char>}, {"else", <else>},
  {"enum", <enum>}, {"goto", <goto>}, {"long", <long>}, {"void", <void>},
  {NULL}};
static const _Keyword keywords5[] = {
  {"break", <break>}, {"catch", <catch>}, {"const", <const>},
  {"defer", <defer>}, {"float", <float>}, {"match", <match>},
  {"raise", <raise>}, {"short", <short>}, {"union", <union>},
  {"while", <while>}, {NULL}};
static const _Keyword keywords6[] = {
  {"double", <double>}, {"extern", <extern>}, {"import", <import>},
  {"inline", <inline>}, {"return", <return>}, {"signed", <signed>},
  {"sizeof", <sizeof>}, {"static", <static>}, {"struct", <struct>},
  {"switch", <switch>}, {NULL}};
static const _Keyword keywords7[] = {
  {"default", <default>}, {"finally", <finally>}, {"typedef", <typedef>},
  {NULL}};
static const _Keyword keywords8[] = {
  {"delegate", <delegate>}, {"protocol", <protocol>},
  {"continue", <continue>}, {"register", <register>},
  {"restrict", <restrict>}, {"threaded", <threaded>},
  {"unsigned", <unsigned>}, {"volatile", <volatile>},
  {"__inline", <inline>}, {NULL}};
static const _Keyword keywords10[] = {
  {"associated", <associated>}, {"__inline__", <inline>},
  {"__restrict", <restrict>}, {NULL}};
static const _Keyword keywords12[] = {
  {"thread_local", <threaded>}, {"__restrict__", <restrict>}, {NULL}};
static const _Keyword keywords13[] = {{"_Thread_local", <threaded>}, {NULL}};

/* Returns the longest supported C or x2c operator prefix, or -1. x2c adds
   `===`, `!==`, `@`, and `@=` to the C operators. The caller supplies a
   nonnull NUL-terminated input. */
int scan_c_operator(char *s) {
  switch (s[0]) {
    case '.': return s[1] == '.' && s[2] == '.' ? 3 : 1;
    case '>': return s[1] == '>' ? 2 + (s[2] == '=') : 1 + (s[1] == '=');
    case '<': return s[1] == '<' ? 2 + (s[2] == '=') : 1 + (s[1] == '=');
    case '+': return s[1] == '=' || s[1] == '+' ? 2 : 1;
    case '-': return s[1] == '=' || s[1] == '-' || s[1] == '>' ? 2 : 1;
    case '&': return s[1] == '=' || s[1] == '&' ? 2 : 1;
    case '|': return s[1] == '=' || s[1] == '|' ? 2 : 1;
    case '=': return s[1] == '=' ? 2 + (s[2] == '=') : 1;
    case '!': return s[1] == '=' ? 2 + (s[2] == '=') : 1;
    case '*': case '/': case '%': case '^': case '@':
      return s[1] == '=' ? 2 : 1;
    case '~': case ';': case ',': case ':': case '(': case ')':
    case '[': case ']': case '{': case '}': case '?':
      return 1;
  }
  return -1;
}

// strings and characters

/* Returns a C String literal's complete byte count, or -1 on malformed or
   truncated input. The caller supplies the opening quote. `status`, when
   nonnull, distinguishes `<malformed>` from `<incomplete>`. */
int scan_c_string_status(char *s, Symbol *status) {
  if (status) *status = <ok>;
  int n = 1;
  while (s[n]) {
    if (s[n] == '\\') {
      int m = _c_escape_status(s + n, status);
      if (m < 0) return -1;
      n += m;
    }
    else if (s[n] == '"') return n + 1;
    else if (s[n] == '\n' || s[n] == '\r') return _fail(status, <malformed>);
    else n++;
  }
  return _fail(status, <incomplete>);
}

/* Returns the same result as `scan_c_string_status` without a status. */
int scan_c_string(char *s) => scan_c_string_status(s, NULL);

/* Returns one complete C character literal's byte count, or -1.
   The caller supplies the opening quote; raw newlines and empty or multi-byte
   unescaped contents are malformed. */
int scan_c_character(char *s) {
  int n = 1;
  if (s[n] == '\\') {
    int m = _c_escape_status(s + n, NULL);
    if (m < 0) return -1;
    n += m;
  }
  else if (!s[n] || s[n] == '\n' || s[n] == '\r' || s[n] == '\'') return -1;
  else n++;
  return s[n] == '\'' ? n + 1 : -1;
}

// percent strings, symbols, and atoms

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
      int m = s[n + 1] == '$' ? 2 : scan_escape_sequence(s + n);
      if (m < 0) return -1;
      n += m;
    }
    else if (s[n] == '$' && s[n + 1] == '$') n += 2;
    else if (s[n] == '$' || s[n] == '"') return n;
    else n++;
  }
  return -1;
}

/* Scans `<simple>` or `<"...">` from borrowed NUL-terminated input.
   Returns zero without an opening angle, a positive byte count on success, or
   -1. `status`, when nonnull, distinguishes `<incomplete>` from `<malformed>`;
   the input must be nonnull. */
int scan_symbol_literal_status(char *s, Symbol *status) {
  if (status) *status = <ok>;
  if (s[0] != '<') return 0;
  if (s[1] == '"') return _quoted_literal(s, status);
  return _simple_literal(s, status);
}

/* Returns the same result as `scan_symbol_literal_status` without a status. */
int scan_symbol_literal(char *s) => scan_symbol_literal_status(s, NULL);

static int _quoted_literal(char *s, Symbol *status) {
  int m = _quoted_spelling(s + 1, status);
  if (m < 0) return -1;
  int n = 1 + m;
  if (s[n] == '>') return n + 1;
  return _fail(status, s[n] ? <malformed> : <incomplete>);
}

/* A simple spelling is nonempty and has no white space. */
static int _simple_literal(char *s, Symbol *status) {
  int n = 1;
  while (s[n]) {
    if (s[n] == '>') return n > 1 ? n + 1 : _fail(status, <malformed>);
    if (s[n] == ' ' || s[n] == '\t' || s[n] == '\r' || s[n] == '\n' ||
        s[n] == '\v' || s[n] == '\f')
      return _fail(status, <malformed>);
    n++;
  }
  return _fail(status, <incomplete>);
}

/* Scans a quoted Symbol spelling from its opening quote through its closing
   quote, using x2c byte escapes. A raw newline is ordinary text. */
static int _quoted_spelling(char *s, Symbol *status) {
  int n = 1;
  while (s[n]) {
    if (s[n] == '\\') {
      int m = _escape_status(s + n, status);
      if (m < 0) return -1;
      n += m;
    }
    else if (s[n] == '"') return n + 1;
    else n++;
  }
  return _fail(status, <incomplete>);
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
  if (s[0] == '"') return _quoted_spelling(s, NULL);
  int n = 0;
  while (s[n]) {
    if (s[n] == '>' && s[n + 1] == '>') return n;
    if (strchr(" \n\t\v\f\r$@", s[n])) return n;
    if (s[n] == '\\' && !s[n + 1]) return -1;
    n += s[n] == '\\' ? 2 : 1;
  }
  return n;
}

/* One atom spelling for Lisp source and `%(...)` list literals. Reader
   punctuation, the x2c escape openers, whitespace, and a comment opener end
   it; a backslash escapes the next byte. Returns zero when no atom starts and
   -1 only for a trailing backslash. `status`, when nonnull, receives `<ok>` or
   `<incomplete>`. */
int scan_atom_status(char *s, Symbol *status) {
  if (status) *status = <ok>;
  if (!s || !*s || strchr("()'`,\"$@{[", *s)) return 0;
  if (s[0] == '\\' && !s[1]) return _fail(status, <incomplete>);
  int n = s[0] == '\\' ? 2 : 1;
  while (s[n]) {
    if (strchr("()'`,\"$@{[", s[n]) || strchr(" \n\t\v\f\r", s[n])) return n;
    if (s[n] == '/' && (s[n + 1] == '/' || s[n + 1] == '*')) return n;
    if (s[n] == '\\' && !s[n + 1]) return _fail(status, <incomplete>);
    n += s[n] == '\\' ? 2 : 1;
  }
  return n;
}

/* Returns the same result as `scan_atom_status` without a status. */
int scan_atom(char *s) => scan_atom_status(s, NULL);

/* escapes

   An escape starts at its backslash. C literals use C escape widths and
   reject raw newlines; percent strings and quoted Symbols keep x2c's
   byte-oriented escapes and multiline behavior. */

/* Returns one x2c byte-oriented escape's length or -1 for malformed or
   truncated input. The caller has already recognized the backslash. */
int scan_escape_sequence(char *s) => _escape_status(s, NULL);

/* Scans x2c byte escapes and classifies truncation separately. */
static int _escape_status(char *s, Symbol *status) {
  switch (s[1]) {
    case '\0': return _fail(status, <incomplete>);
    case 'a': case 'b': case 'f': case 'n': case 'r': case 't': case 'v':
    case '\n': case '\'': case '"': case '?': case '\\': return 2;
    case '\r': return _crlf_escape(s, status);
    case 'x': case 'X': case 'u': case 'U': return _byte_escape(s, status);
    case '0': case '1': case '2': case '3': case '4': case '5': case '6':
    case '7': return _octal_escape(s, status);
  }
  return _fail(status, <malformed>);
}

/* Scans a C escape and classifies truncation separately. */
static int _c_escape_status(char *s, Symbol *status) {
  switch (s[1]) {
    case '\0': return _fail(status, <incomplete>);
    case 'a': case 'b': case 'f': case 'n': case 'r': case 't': case 'v':
    case '\n': case '\'': case '"': case '?': case '\\': return 2;
    case '\r': return _crlf_escape(s, status);
    case '0': case '1': case '2': case '3': case '4': case '5': case '6':
    case '7': return _octal_escape(s, status);
    case 'x': case 'X': return _hex_escape(s, status);
    case 'u': return _universal_escape(s, 4, status);
    case 'U': return _universal_escape(s, 8, status);
  }
  return _fail(status, <malformed>);
}

/* A backslash before CRLF continues the line; a lone CR is malformed. */
static int _crlf_escape(char *s, Symbol *status) {
  if (!s[2]) return _fail(status, <incomplete>);
  return s[2] == '\n' ? 3 : _fail(status, <malformed>);
}

/* One to three octal digits. Three from `\400` up exceed the byte C
   requires. */
static int _octal_escape(char *s, Symbol *status) {
  int n = 2;
  if (s[n] >= '0' && s[n] <= '7') n++;
  if (s[n] >= '0' && s[n] <= '7') n++;
  return n < 4 || s[1] <= '3' ? n : _fail(status, <malformed>);
}

/* x2c's `\x`, `\X`, `\u`, and `\U` take one or two hex digits: one byte. */
static int _byte_escape(char *s, Symbol *status) {
  if (!s[2]) return _fail(status, <incomplete>);
  int n = 2;
  if (_ascii_hex((unsigned char) s[n])) n++;
  if (_ascii_hex((unsigned char) s[n])) n++;
  return n > 2 ? n : _fail(status, <malformed>);
}

/* C's `\x` takes every hex digit that follows it. */
static int _hex_escape(char *s, Symbol *status) {
  if (!s[2]) return _fail(status, <incomplete>);
  if (!_ascii_hex((unsigned char) s[2])) return _fail(status, <malformed>);
  return 2 + _digits(s + 2, 16);
}

/* C's `\u` and `\U` take exactly `count` hex digits. */
static int _universal_escape(char *s, int count, Symbol *status) {
  for (int n = 2; n < 2 + count; n++) {
    if (!s[n]) return _fail(status, <incomplete>);
    if (!_ascii_hex((unsigned char) s[n])) return _fail(status, <malformed>);
  }
  return 2 + count;
}

// source positions

/* Advances one-based `*l` and `*c` across `n` borrowed bytes.
   Each newline increments the line and resets the next byte to column one.
   `n` is nonnegative and all pointers are valid; columns count bytes. */
void scan_next_line_col(char *s, int n, int *l, int *c) {
  int line = *l, col = *c, char *next = s, *end = s + n;
  while (next < end) {
    char *newline = memchr(next, '\n', end - next);
    if (!newline) break;
    line++;
    col = 1;
    next = newline + 1;
  }
  *l = line; *c = col + (end - next);
}
