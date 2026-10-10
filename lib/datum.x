/*  datum.x -- values as Lisp reader text

    Copyright (c) 2026 Gary William Flake

    A datum is a value spelled in the Lisp reader grammar: proper Lists,
    bare Symbols and Atoms, Strings, and numbers. An interface file is plain
    data. A value crossing to or from the project meta helper also carries
    the rest of what a compile-time value can be, as tagged Lists the reader
    reads back. The compiler and the helper both frame their messages with
    this file, so its spellings are their protocol.
*/

#pragma once
#include "x2c.x"

#include <stdio.h>
#include <stdlib.h>

/* tagged spellings

   A tagged datum spells the other values as Lists: `(x2c.void)`,
   `(x2c.null)`, `(x2c.symbol0)`, `(x2c.atom "text")` and
   `(x2c.symbol "text")` for a spelling that is not bare,
   `(x2c.number TAG "text")` for a number the reader would not give back
   with its own family, `(x2c.array ITEM ...)`,
   `(x2c.map (KEY VALUE) ...)`, and `(x2c.token N)`, a compiler Token
   passed by address. A List whose head is one of these tags is written as
   `(x2c.quote LIST)`. */

/* Whether `list` has a tag for its head, which a tagged datum would
   misread. */
static int _tag_headed(List list) {
  if (!list) return 0;
  Var head = list.car();
  if (!head.is_atom()) return 0;
  String text = head.str();
  if (!text.startswith("x2c.")) return 0;
  foreach (String tag, %("x2c.void" "x2c.null" "x2c.symbol0" "x2c.atom"
                         "x2c.symbol" "x2c.number" "x2c.array" "x2c.map"
                         "x2c.token" "x2c.quote"))
    if (text == tag) return 1;
  return 0;
}

// writing

/* Writes `value` to `out` as reader text and returns 1, or returns 0 for a
   value the grammar cannot spell. With `tagged`, the tagged spellings are
   written too; without it, only plain data is. */
int datum_write(Buffer out, Var value, int tagged) {
  if (value is <list>) return _write_list(out, value, tagged);
  if (tagged && value.is_null()) out.write("(x2c.null)");
  else if (tagged && value is void) out.write("(x2c.void)");
  else if (tagged && value is <symbol> && !value.symbol())
    out.write("(x2c.symbol0)");
  else if (value.is_atom()) return _write_atom(out, value, tagged);
  else if (value is <string>) out.write(value.repr());
  /* A floating value is always tagged: `%g` spells 2.0 as `2` and -0.0
     as `-0`, which read back as integers. */
  else if (tagged && (value.is_floating() ||
                      (value.is_integer() && value is not <i32>)))
    _write_number(out, value);
  else if (value.is_integer()) out.printf("%ld", value.integer());
  else if (value.is_floating()) out.printf("%.17g", value.floating());
  else if (tagged && value is <array>) return _write_array(out, value);
  else if (tagged && value is <map>) return _write_map(out, value);
  else if (tagged && value is <token>)
    out.printf("(x2c.token %llu)", (unsigned long long) value.u64);
  else return 0;
  return 1;
}

static int _write_list(Buffer out, List list, int tagged) {
  int quoted = tagged && _tag_headed(list);
  out.write(quoted ? "(x2c.quote (" : "(");
  for (List p = list; p; p = p.cdr()) {
    if (!datum_write(out, p.car(), tagged)) return 0;
    if (p.cdr()) out.write_char(' ');
  }
  out.write(quoted ? "))" : ")");
  return 1;
}

/* An Atom or Symbol is bare when the reader gives its spelling back;
   lib/atom.x owns that test and the reader's Symbol or Atom choice. */
static int _write_atom(Buffer out, Var value, int tagged) {
  String text = value.str();
  if (Atom.bare_spelling(text)) out.write(text);
  else if (tagged)
    out.printf(
      "(%s %s)", value is <symbol> ? "x2c.symbol" : "x2c.atom",
      (char *) text.repr());
  else if (value is <symbol> && value.symbol())
    out.write(value.repr());  // `<"<<">`
  else return 0;
  return 1;
}

static void _write_number(Buffer out, Var value) {
  X2CVarNumeric number;
  value.numeric_decode(number);
  /* The family tag: NaN and the infinities box back from `<f64>`. */
  out.printf("(x2c.number %s \"", (char *) number.tag.str());
  if (number.floating) out.printf("%.21Lg", number.floating_value);
  else if (number.unsigned_value) out.printf("%llu", number.raw);
  else out.printf("%lld", (long long) value.integer());
  out.write("\")");
}

static int _write_array(Buffer out, Array array) {
  out.write("(x2c.array");
  foreach (Var item, array) {
    out.write_char(' ');
    if (!datum_write(out, item, 1)) return 0;
  }
  out.write_char(')');
  return 1;
}

static int _write_map(Buffer out, Map map) {
  out.write("(x2c.map");
  foreach (Var (key, item), map) {
    out.write(" (");
    if (!datum_write(out, key, 1)) return 0;
    out.write_char(' ');
    if (!datum_write(out, item, 1)) return 0;
    out.write_char(')');
  }
  out.write_char(')');
  return 1;
}

// reading

/* Reads the datum at `cursor` in `text` into `out`, decoding the tagged
   spellings `datum_write` makes, and advances `cursor` past it. Returns 0
   at the end of `text`.

   Raises: `<incomplete>` or `<malformed>` for text that is not a datum. */
int datum_read(String text, unsigned &cursor, Var &out) {
  Var value = void;
  if (!datum_read_plain(text, cursor, value)) return 0;
  out = _decode(value);
  return 1;
}

/* Reads the form at `cursor` in `text` into `out` as `Lisp.read` reads it,
   without decoding tagged spellings, and advances `cursor` past it.
   Returns 0 at the end of `text`.

   Raises: `<incomplete>` or `<malformed>` for text that is not a form. */
int datum_read_plain(String text, unsigned &cursor, Var &out) {
  Var value = void;
  unsigned at = cursor;
  if (text) while (_blank(text[at])) at++;
  Array items = $auto([]);
  if (text && text[at] && _plain_form(text, at, value, items, 0))
    cursor = at;
  else if (Lisp.read(NULL, text, cursor, value) != <value>) return 0;
  out = value;
  return 1;
}

/* plain spellings

   The forms `datum_write` spells as plain data, Lists, Strings, decimal
   integers, and bare Atoms, are read here without the Lisp tokenizer,
   which costs most of an interface read. Each reader returns 0 for any
   other spelling, and `Lisp.read` then reads the form from its start, so
   every value is the reader's. `items` holds the elements of the Lists
   being read. */

static int _plain_form(char *s, unsigned &at, Var &out, Array items,
                       int depth) {
  char c = s[at];
  if (c == '(') return _plain_list(s, at, out, items, depth);
  if (c == '"') return _plain_string(s, at, out);
  if (_digit(c) || (c == '-' && _digit(s[at + 1])))
    return _plain_integer(s, at, out);
  return _plain_atom(s, at, out);
}

static int _plain_list(char *s, unsigned &at, Var &out, Array items,
                       int depth) {
  if (depth >= LISP_READ_DEPTH_MAX) return 0;
  int first = items.len();
  for (at++; ; ) {
    while (_blank(s[at])) at++;
    if (s[at] == ')') break;
    Var item = void;
    if (!_plain_form(s, at, item, items, depth + 1)) return 0;
    items.push(item);
  }
  at++;
  List list = NULL;
  for (int i = items.len() - 1; i >= first; i--) list = cons(items[i], list);
  items.truncate(first);
  out = list;
  return 1;
}

static int _plain_string(char *s, unsigned &at, Var &out) {
  unsigned end = at + 1;
  for (; s[end] != '"'; end += s[end] == '\\' ? 2 : 1)
    if (!s[end] || s[end] == '\n' || (s[end] == '\\' && !s[end + 1]))
      return 0;
  if (!_token_end(s[end + 1])) return 0;
  out = _unescaped(String.new_len(s + at + 1, end - at - 1));
  at = end + 1;
  return 1;
}

/* An integer of at most 18 digits, which cannot overflow a `long`. */
static int _plain_integer(char *s, unsigned &at, Var &out) {
  unsigned end = at + (s[at] == '-');
  if (s[end] == '0' && _digit(s[end + 1])) return 0;
  long value = 0;
  for (; _digit(s[end]); end++) {
    if (end - at > 18) return 0;
    value = value * 10 + (s[end] - '0');
  }
  if (!_token_end(s[end])) return 0;
  if (s[at] == '-') value = -value;
  if (value == (int) value) out = (int) value;
  else out = value;
  at = end;
  return 1;
}

static int _plain_atom(char *s, unsigned &at, Var &out) {
  int length = 0;
  while (!_token_end(s[at + length])) length++;
  String spelling = String.new_len(s + at, length);
  if (!Atom.bare_spelling(spelling)) return 0;
  out = Atom.intern(spelling);
  at += length;
  return 1;
}

/* `text.unescape()`, which leaves text without a backslash as it is. */
static String _unescaped(String text) =>
  memchr(text, '\\', text.len()) ? text.unescape() : text;

static int _digit(char c) => c >= '0' && c <= '9';

static int _blank(char c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

/* Whether the reader's token ends before `c`. */
static int _token_end(char c) => !c || c == ')' || _blank(c);

/* The value a tagged spelling stands for. */
static Var _decode(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  if (!_tag_headed(value)) return _decode_list(value);
  List list = value;
  String tag = list.car().str();
  if (tag == "x2c.void") return void;
  if (tag == "x2c.null") return Var.null();
  if (tag == "x2c.symbol0") return (Symbol) 0;
  if (tag == "x2c.atom") return Atom.intern(list.cadr().str());
  if (tag == "x2c.symbol") return Symbol.new(list.cadr().str());
  if (tag == "x2c.number")
    return _decode_number(list.cadr().str(), list.caddr().str());
  if (tag == "x2c.token")
    return Var.new(<token>, (void *) (ulong) list.cadr().integer());
  if (tag == "x2c.quote") return _decode_list(list.cadr());
  if (tag == "x2c.array") return _decode_list(list.cdr()).array();
  return _decode_map(list.cdr());
}

static List _decode_list(List list) {
  Array items = [];
  foreach (Var item, list) items.push(_decode(item));
  return items.list_free();
}

static Var _decode_number(String tag, String text) {
  Symbol target = Symbol.new(tag);
  if (tag.startswith("f") || tag == "ldouble") {
    long double value = strtold(text, NULL);
    return Var.convert(value, target);
  }
  if (tag.startswith("u")) {
    unsigned long long value = strtoull(text, NULL, 10);
    return Var.convert(value, target);
  }
  long long value = strtoll(text, NULL, 10);
  return Var.convert(value, target);
}

static Map _decode_map(List entries) {
  Map map = {};
  foreach (List entry, entries)
    map[_decode(entry.car())] = _decode(entry.cadr());
  return map;
}

// frames

/* Writes `value` to `out` as one frame, its tagged datum's length in
   decimal and a newline before it, and returns 1, or writes nothing and
   returns 0 for a value the grammar cannot spell. */
int datum_frame(Buffer out, Var value) {
  Buffer body = $auto(Buffer.new(0));
  if (!datum_write(body, value, 1)) return 0;
  out.write(%"${body.len()}\n$body");
  return 1;
}

/* Reads the frame at the start of `input` into `value` and sets `used` to
   its size. Returns 0 while `input` holds no complete frame.

   Raises: `<incomplete>` or `<malformed>` for a frame that is not one
   datum. */
int datum_unframe(String input, size_t &used, Var &value) {
  int newline = input.find("\n");
  if (newline <= 0) return 0;
  size_t length = strtoul(input, NULL, 10);
  if (input.len() < newline + 1 + length) return 0;
  String frame = String.new_len(input + newline + 1, length);
  unsigned cursor = 0;
  value = void;
  if (!datum_read(frame, cursor, value)) raise %(malformed (frame $frame));
  used = newline + 1 + length;
  return 1;
}

// compile-time results

/* Returns why the compile-time result `value` cannot become data in the
   program, as `(MESSAGE (NOTE))`, or NULL: it holds a compiler address,
   contains itself, or holds one Array or Map twice. `marks` holds 1 for
   an Array or Map being checked and 2 for one already checked. */
List datum_result_problem(Var value, Map marks) {
  if (value.is_pointer() && value.u64)
    return %("compile-time result is a compiler address"
             ("return data built from the pointed-to values instead"));
  if (value is <list>) return _items_problem(value, marks);
  if (value is not <array> && value is not <map>) return NULL;
  ulong address = (ulong) value.u64;
  if (address in marks)
    return %(${marks[address] == 1
                 ? "compile-time result contains itself"
                 : "compile-time result holds one collection twice"}
             ("each Array and Map in a result is built separately"));
  marks[address] = 1;
  List problem = _items_problem(value, marks);
  if (!problem) marks[address] = 2;
  return problem;
}

/* The first problem among the items of a List, Array, or Map, or NULL. */
static List _items_problem(Var value, Map marks) {
  if (value is <list>)
    foreach (Var item, value.list()) {
      List problem = datum_result_problem(item, marks);
      if (problem) return problem;
    }
  else if (value is <array>)
    foreach (Var item, value.array()) {
      List problem = datum_result_problem(item, marks);
      if (problem) return problem;
    }
  else
    foreach (Var (key, item), (Map) value) {
      List problem = datum_result_problem(key, marks);
      if (!problem) problem = datum_result_problem(item, marks);
      if (problem) return problem;
    }
  return NULL;
}
