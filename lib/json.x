/*  json.x -- JSON text to and from ordinary x2c values

    Copyright (c) 2026 Gary William Flake

    Json owns the crossing between JSON text and ordinary x2c values: an
    object is a Map with String keys, an array an Array, null the all-zero
    Var, and true or false a `JsonBool`. A Map keeps neither member order nor
    duplicate names, so a repeated name keeps its last value and output
    writes names in byte order; `packages/yyjson` serves a program that
    needs either.
*/

#pragma once
#include "private-keywords.x"
#include "x2c.x"
#include "path.x"

/** The receiverless owner of `Json.parse` and the other JSON operations. */
typedef enum Json {
  JSON_NAMESPACE
} Json;

/** A JSON `true` or `false`, kept distinct from the numbers 1 and 0.
    The two values are process-lifetime singletons made by `Json.bool`.
*/
typedef struct JsonBool *JsonBool;

protocol Var(JsonBool);

#include "meta.x"

/* Json reading and writing error conditions.
   Reports expand at their existing owners. */

static macro Stmt $error.boolean.type(Expr $tag) {
  raise %(bad-types (operation "Json.boolean") (tag ${$tag}));
}

static macro Stmt $error.read.file(
  Expr $path, Expr $why, Expr $offset, Expr $line, Expr $column) {
  raise %(malformed (operation "Json.read_file") (path ${$path})
          (reason ${$why}) (offset ${$offset})
          (line ${$line}) (column ${$column}));
}

static macro Stmt $error.read.text(
  Expr $why, Expr $offset, Expr $line, Expr $column) {
  raise %(malformed (operation "Json.parse") (reason ${$why})
          (offset ${$offset}) (line ${$line}) (column ${$column}));
}

static macro Stmt $error.write.depth() {
  raise %(size-limit (operation "Var.json")
          (reason "nesting exceeds 512 levels"));
}

static macro Stmt $error.write.type(Expr $tag) {
  raise %(bad-types (operation "Var.json") (tag ${$tag}));
}

static macro Stmt $error.write.key(Expr $tag) {
  raise %(bad-types (operation "Var.json") (want "String object key")
          (tag ${$tag}));
}

static macro Stmt $error.write.duplicate(Expr $text) {
  raise %(bad-arg (operation "Var.json") (reason "duplicate object name")
          (name ${$text}));
}

static macro Stmt $error.write.nonfinite() {
  raise %(conv-range (operation "Var.json")
          (reason "JSON has no NaN or infinity"));
}

static macro Stmt $error.read.trailing(Expr $reader) =>
  $reader._fail("unexpected text after the value");

static macro Stmt $error.read.depth(Expr $reader) =>
  $reader._fail("nesting exceeds 512 levels");

static macro Stmt $error.read.end(Expr $reader) =>
  $reader._fail("unexpected end of input");

static macro Stmt $error.read.char(Expr $reader) =>
  $reader._fail("unexpected character");

static macro Stmt $error.read.key(Expr $reader) =>
  $reader._fail("expected a string key");

static macro Expression $reason.read.colon() => "expected ':'";

static macro Expression $reason.read.object.sep() => "expected ',' or '}'";

static macro Expression $reason.read.array.sep() => "expected ',' or ']'";

static macro Stmt $error.read.string.end(Expr $reader) =>
  $reader._fail("unterminated string");

static macro Stmt $error.read.control(Expr $reader) =>
  $reader._fail("control character in string");

static macro Stmt $error.read.utf8(Expr $reader) =>
  $reader._fail("invalid UTF-8");

static macro Stmt $error.read.escape(Expr $reader) =>
  $reader._fail("invalid escape");

static macro Stmt $error.read.surrogate(Expr $reader) =>
  $reader._fail("unpaired surrogate");

static macro Stmt $error.read.nul(Expr $reader) =>
  $reader._fail("U+0000 cannot appear in a String");

static macro Stmt $error.read.unicode(Expr $reader) =>
  $reader._fail("invalid \\u escape");

static macro Stmt $error.read.number(Expr $reader) =>
  $reader._fail("invalid number");

static macro Stmt $error.read.range(Expr $reader) =>
  $reader._fail("number out of range");

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JSON_MAX_DEPTH 512

// booleans

static struct JsonBool {
  unsigned long value;
};

static struct JsonBool _json_false = { 0 }, _json_true = { 1 };

/** Boxes a JSON boolean. */
Var JsonBool.var(JsonBool value) => Var.new(<jsonbool>, value);

/** Unboxes a JSON boolean from a `Var` produced by `JsonBool.var`. */
meta native JsonBool Var.jsonbool(Var value) => (JsonBool) value.pointer();

/** Returns `true` or `false`. */
String JsonBool.str(JsonBool value) => value.value ? "true" : "false";

/** Returns `true` or `false`. */
String JsonBool.repr(JsonBool value) => value;

/** Returns nonzero for `true`. */
int JsonBool.truth(JsonBool value) => value.value != 0;

/** Returns the JSON boolean for the truth of `value`. */
Var Json.bool(int value) => (JsonBool) (value ? &_json_true : &_json_false);

/** Reports whether `value` is a JSON boolean. */
int Json.is_bool(Var value) => value is <jsonbool>;

/** Returns 1 for JSON `true` and 0 for JSON `false`.
    Raises: `<bad-types>` when `value` is not a JSON boolean.
*/
int Json.boolean(Var value) {
  if (value is not <jsonbool>) {
    Symbol tag = value.tag();
    $error.boolean.type(tag);
  }
  return !!value.jsonbool();
}

/*  reading

    value  = ws (object | array | string | number | true | false | null) ws
    object = '{' ws [string ws ':' value *(',' ws string ws ':' value)] '}'
    array  = '[' ws [value *(',' value)] ']'
    number = ['-'] ('0' | [1-9] *digit) ['.' 1*digit] [[eE] [+-] 1*digit]
    string = '"' *(unescaped UTF-8 | '\' ["\/bfnrt] | '\u' 4hex) '"'

    Unescaped characters below U+0020 are rejected, `\u` escapes must pair
    surrogates, and U+0000 is rejected because a `String` cannot hold it.
*/

/* One parse of `text`: `at` is the byte being read, `depth` counts the open
   arrays and objects, and `path` names a file for the error details. */
static typedef struct Reader {
  const char *text;
  String path;
  int at, depth;
} Reader;

/** Returns the x2c value of the JSON text `source`.
    Objects become `Map`s, arrays `Array`s, and strings `String`s. A number
    without a fraction or exponent is an `int` `Var` when it fits, then a
    `long`, then an `unsigned long`; any other number is a `double`. JSON
    null is the all-zero `Var`, and true and false are `JsonBool`s. A
    repeated object name keeps its last value.
    Raises: `<malformed>` with `reason`, `offset`, `line`, and `column` details
    when `source` is not one JSON value surrounded only by whitespace, nests
    arrays and objects more than 512 deep, or contains a number too large for
    a `double`, an unpaired surrogate escape, or `\u0000`.
*/
meta native Var Json.parse(String source) => _parse(source, NULL);

/** Returns the x2c value of the JSON file at `path`, as `Json.parse` does.
    Raises: the causes of `Path.read_text`, or `<malformed>` as
    `Json.parse` does, with a `path` detail added.
*/
Var Json.read_file(Path path) => _parse(path.read_text(), path);

static Var _parse(String source, String path) {
  Reader r = {.text = source ? source : "", .path = path};
  Var value = r._value();
  r._space();
  if (r._peek()) $error.read.trailing(r);
  return value;
}

static Var Reader._value(Reader &r) {
  r._space();
  switch (r._peek()) {
    case '{': case '[': {
      if (++r.depth > JSON_MAX_DEPTH) $error.read.depth(r);
      Var nested = r._peek() == '{' ? r._object() : r._array();
      r.depth--;
      return nested;
    }
    case '"': return r._string();
    case 't': r._word("true"); return Json.bool(1);
    case 'f': r._word("false"); return Json.bool(0);
    case 'n': r._word("null"); return (Var) { .u64 = 0 };
    case '-': case '0': case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9': return r._number();
    case '\0': $error.read.end(r);
  }
  $error.read.char(r);
}

static Var Reader._object(Reader &r) {
  Map object = {};
  r.at++;
  r._space();
  if (r._peek() == '}') {
    r.at++;
    return object;
  }
  loop {
    r._space();
    if (r._peek() != '"') $error.read.key(r);
    String name = r._string();
    r._expect(':', $reason.read.colon());
    object[name] = r._value();
    r._space();
    if (r._peek() == '}') {
      r.at++;
      return object;
    }
    r._expect(',', $reason.read.object.sep());
  }
}

static Var Reader._array(Reader &r) {
  Array array = [];
  r.at++;
  r._space();
  if (r._peek() == ']') {
    r.at++;
    return array;
  }
  loop {
    array.push(r._value());
    r._space();
    if (r._peek() == ']') {
      r.at++;
      return array;
    }
    r._expect(',', $reason.read.array.sep());
  }
}

/* Text without escapes becomes a String directly; the Buffer exists only
   once an escape needs decoding. A Buffer's truth is its length, so its
   presence is tested as a pointer. */
static String Reader._string(Reader &r) {
  int run = ++r.at;
  Buffer decoded = NULL;
  defer decoded.free();
  loop {
    int byte = r._peek();
    if (byte == '"') {
      int end = r.at++;
      if (decoded == NULL) return String.new_len(r.text + run, end - run);
      decoded.write_len(r.text + run, end - run);
      return decoded;
    }
    if (byte == '\\') {
      if (decoded == NULL) decoded = Buffer.new(0);
      decoded.write_len(r.text + run, r.at - run);
      r._escape(decoded);
      run = r.at;
    }
    else if (!byte) $error.read.string.end(r);
    else if (byte < 0x20) $error.read.control(r);
    else {
      int length = scan_utf8_length((const unsigned char *) r.text + r.at);
      if (length < 0) $error.read.utf8(r);
      r.at += length;
    }
  }
}

static void Reader._escape(Reader &r, Buffer out) {
  int escape = r.text[++r.at];
  r.at++;
  switch (escape) {
    case '"': case '\\': case '/': out.write_char(escape); return;
    case 'b': out.write_char('\b'); return;
    case 'f': out.write_char('\f'); return;
    case 'n': out.write_char('\n'); return;
    case 'r': out.write_char('\r'); return;
    case 't': out.write_char('\t'); return;
    case 'u': break;
    default:
      r.at -= 2;
      $error.read.escape(r);
  }
  int start = r.at - 2;
  long point = r._hex4();
  if (point >= 0xD800 && point <= 0xDBFF) {
    if (r._peek() != '\\' || r.text[r.at + 1] != 'u') {
      r.at = start;
      $error.read.surrogate(r);
    }
    r.at += 2;
    long low = r._hex4();
    if (low < 0xDC00 || low > 0xDFFF) {
      r.at = start;
      $error.read.surrogate(r);
    }
    point = 0x10000 + ((point - 0xD800) << 10) + (low - 0xDC00);
  }
  else if (point >= 0xDC00 && point <= 0xDFFF) {
    r.at = start;
    $error.read.surrogate(r);
  }
  else if (!point) {
    r.at = start;
    $error.read.nul(r);
  }
  _write_code_point(out, point);
}

static long Reader._hex4(Reader &r) {
  long unit = 0;
  for (int i = 0; i < 4; i++) {
    int digit = scan_ascii_hex_value(r._peek());
    if (digit < 0) $error.read.unicode(r);
    unit = unit * 16 + digit;
    r.at++;
  }
  return unit;
}

/* The grammar check runs first, so strtol, strtoul, and strtod stop exactly
   at `r.at`: none of them sees a sign, radix prefix, or suffix JSON lacks. */
static Var Reader._number(Reader &r) {
  int start = r.at;
  if (r._peek() == '-') r.at++;
  if (r._peek() == '0') r.at++;
  else if (!r._digits()) $error.read.number(r);
  int integral = 1;
  if (r._peek() == '.') {
    integral = 0;
    r.at++;
    if (!r._digits()) $error.read.number(r);
  }
  if ((r._peek() | 32) == 'e') {
    integral = 0;
    r.at++;
    if (r._peek() == '+' || r._peek() == '-') r.at++;
    if (!r._digits()) $error.read.number(r);
  }
  if (scan_ascii_digit(r._peek())) $error.read.number(r);

  const char *spelling = r.text + start;
  errno = 0;
  if (integral) {
    long number = strtol(spelling, NULL, 10);
    if (!errno) {
      if (number >= INT_MIN && number <= INT_MAX) return (int) number;
      return number;
    }
    if (*spelling != '-') {
      errno = 0;
      unsigned long positive = strtoul(spelling, NULL, 10);
      if (!errno) return Var.box_ulong(positive);
    }
  }
  double number = strtod(spelling, NULL);
  if (isinf(number)) {
    r.at = start;
    $error.read.range(r);
  }
  return number;
}

static int Reader._digits(Reader &r) {
  int start = r.at;
  while (scan_ascii_digit(r._peek())) r.at++;
  return r.at - start;
}

static void Reader._word(Reader &r, const char *word) {
  size_t length = strlen(word);
  if (strncmp(r.text + r.at, word, length)) $error.read.char(r);
  r.at += length;
}

static void Reader._expect(Reader &r, char byte, const char *why) {
  r._space();
  if (r._peek() != byte) r._fail(why);
  r.at++;
}

static void Reader._space(Reader &r) {
  loop {
    switch (r._peek()) {
      case ' ': case '\t': case '\n': case '\r': r.at++; break;
      default: return;
    }
  }
}

static int Reader._peek(Reader &r) =>
  (unsigned char) r.text[r.at];

static void Reader._fail(Reader &r, String why) {
  int line = 1, column = 1, offset = r.at;
  scan_next_line_col((char *) r.text, offset, &line, &column);
  if (r.path)
    $error.read.file(r.path, why, offset, line, column);
  $error.read.text(why, offset, line, column);
}

/*  writing

    Compact output has no whitespace. Pretty output puts each member and
    element on its own line, indented two spaces per level, and writes empty
    containers as `[]` and `{}`; it matches Python's
    `json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False)` for
    integers, strings, and containers.
*/

/* One write: the output Buffer and whether it is indented. */
static typedef struct Writer {
  Buffer out;
  int pretty;
} Writer;

/** Returns `value` as compact JSON text.
    `Map` names are written in byte order and must be `String`s or
    `Symbol`s with distinct spellings; a `Symbol` value is written as a
    string. A `List` is written as an array. A `double` is written with the
    fewest digits that read back to the same value. Each maximal ill-formed
    UTF-8 subsequence in a string is written as U+FFFD, as Python and
    JavaScript decoders replace it.
    Raises: `<bad-types>` for a value or name JSON cannot hold, `<bad-arg>`
    for a `String` and a `Symbol` name with the same spelling,
    `<conv-range>` for NaN or an infinity, or `<size-limit>` for nesting
    deeper than 512 levels.
*/
String Var.json(Var value) => _json(value, 0);

/** Returns `value` as JSON text indented two spaces per level.
    Raises: the causes of `Var.json`.
*/
String Var.pretty_json(Var value) => _json(value, 1);

/** Replaces the file at `path` with `value` as compact JSON text.
    Raises: the causes of `Var.json` and `Path.write_text`.
*/
void Json.write_file(Var value, Path path) {
  path.write_text(value.json());
}

static String _json(Var value, int pretty) {
  Buffer out = $auto(Buffer.new(0));
  Writer w = {.out = out, .pretty = pretty};
  w._value(value, 0);
  return out;
}

static void Writer._value(Writer &w, Var value, int depth) {
  if (depth > JSON_MAX_DEPTH)
    $error.write.depth();
  if (value.is_null()) w.out.write("null");
  else if (value is <jsonbool>) w.out.write(value.jsonbool().str());
  else if (value is <string> || value.is_atom())
    _write_string(w.out, value.str());
  else if (value.is_integer()) _write_integer(w.out, value);
  else if (value.is_floating()) _write_double(w.out, value.floating());
  else if (value is <array> || value is <list>) w._elements(value, depth);
  else if (value is <map>) w._members(value, depth);
  else {
    Symbol tag = value.tag();
    $error.write.type(tag);
  }
}

static void Writer._elements(Writer &w, Var sequence, int depth) {
  int count = 0;
  w.out.write_char('[');
  foreach (Var element, sequence) {
    if (count++) w.out.write_char(',');
    w._line(depth + 1);
    w._value(element, depth + 1);
  }
  if (count) w._line(depth);
  w.out.write_char(']');
}

static void Writer._members(Writer &w, Map object, int depth) {
  Array names = $auto([]);
  foreach (Var (name, member), object) {
    if (name is not <string> && !name.is_atom()) {
      Symbol tag = name.tag();
      $error.write.key(tag);
    }
    names.push(name);
  }
  names.sort_by(%!(name) => name.str());
  int count = 0;
  String previous = NULL;
  w.out.write_char('{');
  foreach (Var name, names) {
    String text = name.str();
    // A String and a Symbol with the same spelling would write one name twice.
    if (count && text == previous)
      $error.write.duplicate(text);
    previous = text;
    if (count++) w.out.write_char(',');
    w._line(depth + 1);
    _write_string(w.out, text);
    w.out.write(w.pretty ? ": " : ":");
    w._value(object[name], depth + 1);
  }
  if (count) w._line(depth);
  w.out.write_char('}');
}

static void Writer._line(Writer &w, int depth) {
  if (w.pretty) w.out.newline().write_repeat(' ', 2 * depth);
}

static void _write_string(Buffer out, String text) {
  const unsigned char *bytes = (const unsigned char *) text;
  int length = text.len(), run = 0;
  out.write_char('"');
  for (int at = 0; at < length;) {
    int byte = bytes[at];
    const char *escape = NULL;
    switch (byte) {
      case '"':  escape = "\\\""; break;
      case '\\': escape = "\\\\"; break;
      case '\b': escape = "\\b"; break;
      case '\f': escape = "\\f"; break;
      case '\n': escape = "\\n"; break;
      case '\r': escape = "\\r"; break;
      case '\t': escape = "\\t"; break;
    }
    int sequence = escape || byte < 0x20 ? -1 : scan_utf8_length(bytes + at);
    if (sequence > 0) {
      at += sequence;
      continue;
    }
    out.write_len(text + run, at - run);
    if (escape) out.write(escape);
    else if (byte < 0x20) out.printf("\\u%04x", byte);
    else _write_code_point(out, 0xFFFD);
    run = at -= sequence;
  }
  // The empty String is NULL, so an empty tail must not offset it.
  if (run < length) out.write_len(text + run, length - run);
  out.write_char('"');
}

static void _write_integer(Buffer out, Var value) {
  if (value is <ulong>) out.printf("%lu", value.ulong_value());
  else if (value is <ullong>) out.printf("%llu", value.ulong_long_value());
  else if (value is <llong>) out.printf("%lld", value.long_long_value());
  else out.printf("%ld", value.integer());
}

/* The shortest `%e` spelling that reads back exactly supplies the digits;
   positional notation is used for decimal exponents from -4 through 15, as
   Python's `repr` does, and a fraction or exponent is always present so the
   text reads back as a `double`. */
static void _write_double(Buffer out, double number) {
  if (!isfinite(number))
    $error.write.nonfinite();
  char text[32];
  int precision = 0;
  do snprintf(text, sizeof(text), "%.*e", precision++, number);
  while (strtod(text, NULL) != number);
  int exponent = atoi(strchr(text, 'e') + 1), decimals;
  if (exponent >= -4 && exponent < 16) {
    decimals = precision - 1 - exponent;
    snprintf(text, sizeof(text), "%.*f", decimals > 0 ? decimals : 0, number);
  }
  out.write(text);
  if (!strpbrk(text, ".e")) out.write(".0");
}

/* UTF-8

   Reading validates each unescaped sequence with `scan_utf8_length` and
   decodes `\u` escapes; writing replaces each ill-formed subpart with
   U+FFFD. */

static void _write_code_point(Buffer out, long point) {
  if (point < 0x80) {
    out.write_char(point);
    return;
  }
  char bytes[4];
  int length = point < 0x800 ? 2 : point < 0x10000 ? 3 : 4;
  for (int i = length - 1; i > 0; i--) {
    bytes[i] = 0x80 | (point & 0x3F);
    point >>= 6;
  }
  bytes[0] = (0xF0 << (4 - length)) | point;
  out.write_len(bytes, length);
}
