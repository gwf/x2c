/*  datum.x -- values as Lisp reader text

    Copyright (c) 2026 Gary William Flake

    A datum is a value spelled in the Lisp reader grammar: proper Lists,
    bare Symbols and Atoms, Strings, and numbers. An interface file is plain
    data. A value crossing to or from the project meta helper also carries
    the rest of what a compile-time value can be, as tagged Lists the reader
    reads back: `(x2c.void)`, `(x2c.symbol0)`, `(x2c.atom "text")` and
    `(x2c.symbol "text")` for a spelling that is not bare,
    `(x2c.number TAG "text")` for a number the reader would not give back
    with its own family, `(x2c.array ITEM ...)`, `(x2c.map (KEY VALUE)
    ...)`, and `(x2c.token N)`, a compiler Token passed by address. A List
    whose head is one of these tags is written as `(x2c.quote LIST)`.
*/

#pragma once
#include "x2c.x"

#pragma private

#include <stdio.h>
#include <stdlib.h>

/* Whether `value` is a List the tagged spellings would misread. */
static int _datum_tagged(Var value) {
  if (value is not <list> || value.is_nil()) return 0;
  Var head = value.car();
  if (!head.is_atom()) return 0;
  String text = head.str();
  if (!text.startswith("x2c.")) return 0;
  foreach (String tag, %("x2c.void" "x2c.symbol0" "x2c.atom" "x2c.symbol"
                         "x2c.number"
                         "x2c.array" "x2c.map" "x2c.token" "x2c.quote"))
    if (text == tag) return 1;
  return 0;
}

static void _datum_number(Buffer out, Var value) {
  X2CVarNumeric number;
  value.numeric_decode(number);
  out.printf("(x2c.number %s \"", (char *) value.tag().str());
  if (number.floating) out.printf("%.21Lg", number.floating_value);
  else if (number.unsigned_value) out.printf("%llu", number.raw);
  else out.printf("%lld", (long long) value.integer());
  out.write("\")");
}

/* Writes `value` to `out` as reader text and returns 1, or returns 0 for a
    value the grammar cannot spell. With `tagged`, the tagged spellings this
    file describes are written too; without it, only plain data is. */
int datum_write(Buffer out, Var value, int tagged) {
  if (tagged && _datum_tagged(value)) {
    out.write("(x2c.quote ");
    List list = value;
    out.write_char('(');
    for (List p = list; p; p = p.cdr()) {
      if (p != list) out.write_char(' ');
      if (!datum_write(out, p.car(), tagged)) return 0;
    }
    out.write("))");
  }
  else if (value is <list>) {
    List list = value;
    out.write_char('(');
    for (List p = list; p; p = p.cdr()) {
      if (p != list) out.write_char(' ');
      if (!datum_write(out, p.car(), tagged)) return 0;
    }
    out.write_char(')');
  }
  else if (tagged && value is void) out.write("(x2c.void)");
  else if (tagged && value is <symbol> && !value.symbol())
    out.write("(x2c.symbol0)");
  else if (value.is_atom()) {
    // lib/atom.x owns bare spelling and the reader's Symbol/Atom choice.
    String text = value.str();
    if (Atom.bare_spelling(text)) out.write(text);
    else if (tagged)
      out.printf("(%s %s)", value is <symbol> ? "x2c.symbol" : "x2c.atom",
                 (char *) text.repr());
    else if (value is <symbol>) out.write(value.repr());  // `<"<<">`
    else return 0;
  }
  else if (value is <string>) out.write(value.repr());
  /* A floating value is always tagged: `%g` spells 2.0 as `2` and -0.0
     as `-0`, which read back as integers. */
  else if (tagged && (value.is_floating() ||
                      (value.is_integer() && value is not <i32>)))
    _datum_number(out, value);
  else if (value.is_integer()) out.printf("%ld", value.integer());
  else if (value.is_floating()) out.printf("%.17g", value.floating());
  else if (tagged && value is <array>) {
    out.write("(x2c.array");
    foreach (Var item, value.array()) {
      out.write_char(' ');
      if (!datum_write(out, item, tagged)) return 0;
    }
    out.write_char(')');
  }
  else if (tagged && value is <map>) {
    out.write("(x2c.map");
    foreach (Var (key, item), (Map) value) {
      out.write(" (");
      if (!datum_write(out, key, tagged)) return 0;
      out.write_char(' ');
      if (!datum_write(out, item, tagged)) return 0;
      out.write_char(')');
    }
    out.write_char(')');
  }
  else if (tagged && value is <token>)
    out.printf("(x2c.token %llu)", (unsigned long long) value.u64);
  else return 0;
  return 1;
}

static Var _datum_decode(Var value);

static Var _datum_decode_number(String tag, String text) {
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

static List _datum_decode_list(List list) {
  Array items = [];
  foreach (Var item, list) items.push(_datum_decode(item));
  return items.list_free();
}

/* The value a tagged spelling stands for. */
static Var _datum_decode(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  if (!_datum_tagged(value)) return _datum_decode_list(value);
  List list = value;
  String tag = list.car().str();
  if (tag == "x2c.void") return void;
  if (tag == "x2c.symbol0") return (Symbol) 0;
  if (tag == "x2c.atom") return Atom.intern(list.cadr().str());
  if (tag == "x2c.symbol") return Symbol.new(list.cadr().str());
  if (tag == "x2c.number")
    return _datum_decode_number(list.cadr().str(), list.caddr().str());
  if (tag == "x2c.token")
    return Var.new(<token>, (void *) (unsigned long long) list.cadr().integer());
  if (tag == "x2c.quote") return _datum_decode_list(list.cadr());
  if (tag == "x2c.array") {
    Array items = [];
    foreach (Var item, list.cdr()) items.push(_datum_decode(item));
    return items;
  }
  Map map = {};
  foreach (List entry, list.cdr())
    map[_datum_decode(entry.car())] = _datum_decode(entry.cadr());
  return map;
}

/* Reads the datum at `cursor` in `text` into `out`, decoding the tagged
    spellings `datum_write` makes, and advances `cursor` past it. Returns 0
    at the end of `text`.

    Raises: `<incomplete>` or `<malformed>` for text that is not a datum. */
int datum_read(String text, unsigned &cursor, Var &out) {
  Var value = void;
  if (Lisp.read(NULL, text, cursor, value) != <value>) return 0;
  out = _datum_decode(value);
  return 1;
}

/** Returns why the compile-time result `value` cannot become data in the
    program, as `(MESSAGE (NOTE))`, or NULL: it holds a compiler address,
    contains itself, or holds one Array or Map twice. `marks` holds 1 for
    an Array or Map being checked and 2 for one already checked. */
List datum_result_problem(Var value, Map marks) {
  if (value.is_pointer() && value.u64)
    return %("compile-time result is a compiler address"
             ("return data built from the pointed-to values instead"));
  if (value is <list>) {
    foreach (Var item, value.list()) {
      List problem = datum_result_problem(item, marks);
      if (problem) return problem;
    }
    return NULL;
  }
  if (value is not <array> && value is not <map>) return NULL;
  ulong address = (ulong) value.u64;
  if (address in marks)
    return %(${marks[address] == 1
                 ? "compile-time result contains itself"
                 : "compile-time result holds one collection twice"}
             ("each Array and Map in a result is built separately"));
  marks[address] = 1;
  if (value is <array>)
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
  marks[address] = 2;
  return NULL;
}
