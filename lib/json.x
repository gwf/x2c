/*  json.x -- JSON text to and from ordinary x2c values

    Copyright (c) 2026 Gary William Flake

    A JSON object becomes a `Map` with `String` keys, an array an `Array`, a
    string a `String`, a number an integer or `double` `Var`, null the
    all-zero `Var`, and true or false a `JsonBool`. The names match the
    converting surface of `packages/yyjson`, which a program can use instead
    when it needs object order, duplicate names, or numeric intent. A `Map`
    has none of those: a repeated name keeps its last value, and output lists
    names in byte order so the same value always writes the same text.

    Input follows the RFC 8259 grammar. Rejected text raises `<bad-arg>` with
    the byte `offset`, one-based `line` and byte `column`, and a `why`.
*/

#pragma once
$(import "private-keywords.xmacro")
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

#pragma private

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define JSON_MAX_DEPTH 512

// booleans

struct JsonBool {
  unsigned long value;
};

static struct JsonBool _json_false = { 0 }, _json_true = { 1 };

/** Boxes a JSON boolean. */
Var JsonBool.var(JsonBool value) => Var.new(<jsonbool>, value);

/** Unboxes a JSON boolean from a `Var` produced by `JsonBool.var`. */
JsonBool Var.jsonbool(Var value) => (JsonBool) value.pointer();

/** Returns `true` or `false`. */
String JsonBool.str(JsonBool value) => value.value ? "true" : "false";

/** Returns `true` or `false`. */
String JsonBool.repr(JsonBool value) => value.str();

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
    raise %(bad-types (operation "Json.boolean") (tag $tag));
  }
  return value.jsonbool().truth();
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

typedef struct JsonReader {
  const char *text;
  String path;
  int at, length, depth;
} *JsonReader;

static void JsonReader._fail(JsonReader j, const char *why) {
  int line = 1, column = 1, offset = j.at;
  scan_next_line_col((char *) j.text, offset, &line, &column);
  String reason = why;
  if (j.path)
    raise %(bad-arg (operation "Json.read_file") (path ${j.path})
            (why $reason) (offset $offset) (line $line) (column $column));
  raise %(bad-arg (operation "Json.parse") (why $reason)
          (offset $offset) (line $line) (column $column));
}

static int JsonReader._peek(JsonReader j) =>
  (unsigned char) j.text[j.at];

static void JsonReader._space(JsonReader j) {
  loop {
    switch (j._peek()) {
      case ' ': case '\t': case '\n': case '\r': j.at++; break;
      default: return;
    }
  }
}

static void JsonReader._expect(JsonReader j, char byte, const char *why) {
  j._space();
  if (j._peek() != byte) j._fail(why);
  j.at++;
}

static void JsonReader._word(JsonReader j, const char *word) {
  size_t length = strlen(word);
  if (strncmp(j.text + j.at, word, length)) j._fail("unexpected character");
  j.at += length;
}

static int JsonReader._digits(JsonReader j) {
  int start = j.at;
  while (scan_ascii_digit(j._peek())) j.at++;
  return j.at - start;
}

/* The grammar check runs first, so strtol, strtoul, and strtod stop exactly
   at `j.at`: none of them sees a sign, radix prefix, or suffix JSON lacks. */
static Var JsonReader._number(JsonReader j) {
  int start = j.at;
  if (j._peek() == '-') j.at++;
  if (j._peek() == '0') j.at++;
  else if (!j._digits()) j._fail("invalid number");
  int integral = 1;
  if (j._peek() == '.') {
    integral = 0;
    j.at++;
    if (!j._digits()) j._fail("invalid number");
  }
  if ((j._peek() | 32) == 'e') {
    integral = 0;
    j.at++;
    if (j._peek() == '+' || j._peek() == '-') j.at++;
    if (!j._digits()) j._fail("invalid number");
  }
  if (scan_ascii_digit(j._peek())) j._fail("invalid number");

  const char *spelling = j.text + start;
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
    j.at = start;
    j._fail("number out of range");
  }
  return number;
}

static int _hex_digit(int byte) {
  if (scan_ascii_digit(byte)) return byte - '0';
  byte |= 32;
  return byte >= 'a' && byte <= 'f' ? byte - 'a' + 10 : -1;
}

static long JsonReader._hex4(JsonReader j) {
  long unit = 0;
  for (int i = 0; i < 4; i++) {
    int digit = _hex_digit(j._peek());
    if (digit < 0) j._fail("invalid \\u escape");
    unit = unit * 16 + digit;
    j.at++;
  }
  return unit;
}

/* Returns the length of the well-formed UTF-8 sequence at `s`, or 0. Overlong
   forms, surrogates, and code points above U+10FFFF are ill-formed. */
static int _utf8_length(const unsigned char *s) {
  int length, low = 0x80, high = 0xBF;
  if (s[0] < 0x80) return 1;
  if (s[0] < 0xC2) return 0;
  if (s[0] < 0xE0) length = 2;
  else if (s[0] < 0xF0) {
    length = 3;
    if (s[0] == 0xE0) low = 0xA0;
    if (s[0] == 0xED) high = 0x9F;
  }
  else if (s[0] < 0xF5) {
    length = 4;
    if (s[0] == 0xF0) low = 0x90;
    if (s[0] == 0xF4) high = 0x8F;
  }
  else return 0;
  if (s[1] < low || s[1] > high) return 0;
  for (int i = 2; i < length; i++)
    if (s[i] < 0x80 || s[i] > 0xBF) return 0;
  return length;
}

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

static void JsonReader._escape(JsonReader j, Buffer out) {
  int escape = j.text[++j.at];
  j.at++;
  switch (escape) {
    case '"': case '\\': case '/': out.write_char(escape); return;
    case 'b': out.write_char('\b'); return;
    case 'f': out.write_char('\f'); return;
    case 'n': out.write_char('\n'); return;
    case 'r': out.write_char('\r'); return;
    case 't': out.write_char('\t'); return;
    case 'u': break;
    default:
      j.at -= 2;
      j._fail("invalid escape");
  }
  int start = j.at - 2;
  long point = j._hex4();
  if (point >= 0xD800 && point <= 0xDBFF) {
    if (j._peek() != '\\' || j.text[j.at + 1] != 'u') {
      j.at = start;
      j._fail("unpaired surrogate");
    }
    j.at += 2;
    long low = j._hex4();
    if (low < 0xDC00 || low > 0xDFFF) {
      j.at = start;
      j._fail("unpaired surrogate");
    }
    point = 0x10000 + ((point - 0xD800) << 10) + (low - 0xDC00);
  }
  else if (point >= 0xDC00 && point <= 0xDFFF) {
    j.at = start;
    j._fail("unpaired surrogate");
  }
  else if (!point) {
    j.at = start;
    j._fail("U+0000 cannot appear in a String");
  }
  _write_code_point(out, point);
}

/* Text without escapes becomes a String directly; the Buffer exists only
   once an escape needs decoding. A Buffer's truth is its length, so its
   presence is tested as a pointer. */
static String JsonReader._string(JsonReader j) {
  int run = ++j.at;
  Buffer decoded = NULL;
  loop {
    int byte = j._peek();
    if (byte == '"') {
      String text = (void *) decoded == NULL
        ? String.new_len(j.text + run, j.at - run)
        : decoded.write_len(j.text + run, j.at - run).str_free();
      j.at++;
      return text;
    }
    if (byte == '\\') {
      if ((void *) decoded == NULL) decoded = Buffer.new(0);
      decoded.write_len(j.text + run, j.at - run);
      j._escape(decoded);
      run = j.at;
    }
    else if (!byte) j._fail("unterminated string");
    else if (byte < 0x20) j._fail("control character in string");
    else {
      int length = _utf8_length((const unsigned char *) j.text + j.at);
      if (!length) j._fail("invalid UTF-8");
      j.at += length;
    }
  }
}

static Var JsonReader._array(JsonReader j) {
  Array array = [];
  j.at++;
  j._space();
  if (j._peek() == ']') {
    j.at++;
    return array;
  }
  loop {
    array.push(j._value());
    j._space();
    if (j._peek() == ']') {
      j.at++;
      return array;
    }
    j._expect(',', "expected ',' or ']'");
  }
}

static Var JsonReader._object(JsonReader j) {
  Map object = {};
  j.at++;
  j._space();
  if (j._peek() == '}') {
    j.at++;
    return object;
  }
  loop {
    j._space();
    if (j._peek() != '"') j._fail("expected a string key");
    String name = j._string();
    j._expect(':', "expected ':'");
    object[name] = j._value();
    j._space();
    if (j._peek() == '}') {
      j.at++;
      return object;
    }
    j._expect(',', "expected ',' or '}'");
  }
}

static Var JsonReader._value(JsonReader j) {
  j._space();
  switch (j._peek()) {
    case '{': case '[': {
      if (++j.depth > JSON_MAX_DEPTH) j._fail("nesting exceeds 512 levels");
      Var nested = j._peek() == '{' ? j._object() : j._array();
      j.depth--;
      return nested;
    }
    case '"': return j._string();
    case 't': j._word("true"); return Json.bool(1);
    case 'f': j._word("false"); return Json.bool(0);
    case 'n': j._word("null"); return (Var) { .u64 = 0 };
    case '-': case '0': case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9': return j._number();
    case '\0': j._fail("unexpected end of input");
  }
  j._fail("unexpected character");
}

static Var _parse(String source, String path) {
  struct JsonReader reader = {
    .text = source ? source : "", .path = path, .length = source.len()
  };
  JsonReader j = &reader;
  Var value = j._value();
  j._space();
  if (j.at != j.length) j._fail("unexpected text after the value");
  return value;
}

/** Returns the x2c value of the JSON text `source`.
    Objects become `Map`s, arrays `Array`s, and strings `String`s. A number
    without a fraction or exponent is an `int` `Var` when it fits, then a
    `long`, then an `unsigned long`; any other number is a `double`. JSON
    null is the all-zero `Var`, and true and false are `JsonBool`s. A
    repeated object name keeps its last value.
    Raises: `<bad-arg>` with `why`, `offset`, `line`, and `column` details
    when `source` is not one JSON value surrounded only by whitespace, nests
    arrays and objects more than 512 deep, or contains a number too large for
    a `double`, an unpaired surrogate escape, or `\u0000`.
*/
Var Json.parse(String source) => _parse(source, NULL);

/** Returns the x2c value of the JSON file at `path`, as `Json.parse` does.
    Raises: the causes of `Path.read_text`, or `<bad-arg>` as
    `Json.parse` does, with a `path` detail added.
*/
Var Json.read_file(Path path) => _parse(path.read_text(), path);

/*  writing

    Compact output has no whitespace. Pretty output puts each member and
    element on its own line, indented two spaces per level, and writes empty
    containers as `[]` and `{}`; it matches Python's
    `json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False)` for
    integers, strings, and containers.
*/

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
    if (!escape && byte >= 0x20) {
      int sequence = _utf8_length(bytes + at);
      if (!sequence)
        raise %(bad-arg (operation "Var.json") (why "invalid UTF-8")
                (offset $at));
      at += sequence;
      continue;
    }
    out.write_len(text + run, at - run);
    if (escape) out.write(escape);
    else out.printf("\\u%04x", byte);
    run = ++at;
  }
  // The empty String is NULL, so an empty tail must not offset it.
  if (run < length) out.write_len(text + run, length - run);
  out.write_char('"');
}

/* The shortest `%e` spelling that reads back exactly supplies the digits;
   positional notation is used for decimal exponents from -4 through 15, as
   Python's `repr` does, and a fraction or exponent is always present so the
   text reads back as a `double`. */
static void _write_double(Buffer out, double number) {
  if (!isfinite(number)) {
    raise %(conv-range (operation "Var.json")
            (why "JSON has no NaN or infinity"));
  }
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

static void _write_integer(Buffer out, Var value) {
  if (value is <ulong>) out.printf("%lu", value.ulong_value());
  else if (value is <ullong>) out.printf("%llu", value.ulong_long_value());
  else if (value is <llong>) out.printf("%lld", value.long_long_value());
  else out.printf("%ld", value.integer());
}

static void _write_line(Buffer out, int pretty, int depth) {
  if (pretty) out.newline().write_repeat(' ', 2 * depth);
}

static void _write_elements(Buffer out, Var sequence, int pretty, int depth) {
  int count = 0;
  out.write_char('[');
  foreach (Var element, sequence) {
    if (count++) out.write_char(',');
    _write_line(out, pretty, depth + 1);
    _write(out, element, pretty, depth + 1);
  }
  if (count) _write_line(out, pretty, depth);
  out.write_char(']');
}

static void _write_members(Buffer out, Map object, int pretty, int depth) {
  Array names = $auto([]);
  foreach (Var (name, member), object) {
    if (name is not <string> && !name.is_atom()) {
      Symbol tag = name.tag();
      raise %(bad-types (operation "Var.json") (want "String object key")
              (tag $tag));
    }
    names.push(name);
  }
  names.sort_by(%!(name) => name.str());
  int count = 0;
  out.write_char('{');
  foreach (Var name, names) {
    if (count++) out.write_char(',');
    _write_line(out, pretty, depth + 1);
    _write_string(out, name.str());
    out.write(pretty ? ": " : ":");
    _write(out, object[name], pretty, depth + 1);
  }
  if (count) _write_line(out, pretty, depth);
  out.write_char('}');
}

static void _write(Buffer out, Var value, int pretty, int depth) {
  if (depth > JSON_MAX_DEPTH) {
    raise %(size-limit (operation "Var.json")
            (why "nesting exceeds 512 levels"));
  }
  if (value.is_null()) out.write("null");
  else if (value is <jsonbool>) out.write(value.jsonbool().str());
  else if (value is <string> || value is <symbol>)
    _write_string(out, value.str());
  else if (value.is_integer()) _write_integer(out, value);
  else if (value.is_floating()) _write_double(out, value.floating());
  else if (value is <array> || value is <list>)
    _write_elements(out, value, pretty, depth);
  else if (value is <map>) _write_members(out, value, pretty, depth);
  else {
    Symbol tag = value.tag();
    raise %(bad-types (operation "Var.json") (tag $tag));
  }
}

static String _json(Var value, int pretty) {
  Buffer out = $auto(Buffer.new(0));
  _write(out, value, pretty, 0);
  return out.str();
}

/** Returns `value` as compact JSON text.
    `Map` names are written in byte order and must be `String`s or
    `Symbol`s; a `Symbol` value is written as a string. A `List` is written
    as an array. A `double` is written with the fewest digits that read back
    to the same value.
    Raises: `<bad-types>` for a value or name JSON cannot hold,
    `<conv-range>` for NaN or an infinity, `<bad-arg>` for a string that is
    not UTF-8, or `<size-limit>` for nesting deeper than 512 levels.
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
