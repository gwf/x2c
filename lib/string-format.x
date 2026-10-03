/*  string-format.x -- checked formatting of `Var` values into a `String`

    Copyright (c) 2025 Gary William Flake

    `String.format` parses a checked subset of C's format syntax itself,
    converts each `Var` value to the C type its conversion names, and prints
    it through `Buffer.printf`, so a format read at run time cannot pass C a
    mismatched argument. `String.printf`, which hands C arguments straight
    to `vsnprintf`, stays with the other constructors in `string.x`.
*/

#pragma once

#include "string.x"

#pragma private

#include <limits.h>
#include <stdio.h>
#include <string.h>

#include "var.x"
#include "list.x"
#include "buffer.x"
#include "exception.x"

$(import "string-format-errors.xmacro")

// representation

/* One conversion specification: the flag bits, the width or zero for
   none, the precision or a negative value for none, a length modifier, and
   the conversion byte. */
typedef struct Spec {
  int flags, width, precision, modifier;
  char conversion;
} Spec;

// A flag's bit is its position here, so `-` is `FORMAT_LEFT`.
static const char _format_flags[] = "-+ #0";
enum { FORMAT_LEFT = 1 };

// The length modifiers, spelled at their values; zero is none.
static const char *const _format_modifiers[] = {"", "hh", "h", "l", "ll", "L"};
enum {
  FORMAT_HH = 1, FORMAT_H = 2, FORMAT_L = 3, FORMAT_LL = 4, FORMAT_CAP_L = 5
};

/* One pass of `String.format`. The bytes from `literal` to `cursor` are
   text not yet written, `offset` is the `%` of the conversion being read,
   which its errors report, and `args` holds the values still to take. */
typedef struct Format {
  String fmt, int length, literal, cursor, offset, List args, Buffer out;
} Format;

// formatting

/** Formats `values` through a checked, C-style subset of `fmt`.
    The receiver is decoded runtime text, so this fixed-signature operation is
    safe to call through the interpreter as `fmt.format(values)`. It supports
    `%%`, flags `-+ #0`, numeric or `*` width and precision, integer
    conversions `d i o u x X` with `hh h l ll`, floating conversions
    `f F e E g G a A` with default, `l`, or `L`, and `%c` and `%s`.
    Numeric values are converted with `Var.convert`; `%s` uses `Var.str`.

    Pointer and write-count conversions, wide strings and characters,
    positional arguments, `j z t` lengths, malformed formats, and missing or
    excess values are rejected. `%c` also rejects NUL because canonical
    `String`s cannot contain it. Output is staged privately and no result is
    published on failure. Formatting follows the process locale.

    Raises: `<format>` with byte `offset` and `reason`; numeric and string
    conversion failures are nested as `cause`. Allocation failures may also
    transfer while staging or canonicalizing the result.
*/
String String.format(String fmt, List values) {
  Buffer out = $auto(Buffer.new(0));
  Format f = {.fmt = fmt, .length = fmt.len(), .args = values, .out = out};
  while (f.cursor < f.length)
    if (f.byte() == '%') f.conversion();
    else f.cursor++;
  f.write_literal();
  if (f.args) _format_error(f.length, $format.reason.excess_values());
  return out;
}

/* Writes the text before the `%` at the cursor, then the conversion that
   `%` starts. */
static void Format.conversion(Format &f) {
  f.write_literal();
  f.offset = f.cursor++;
  f.need_byte();
  if (f.byte() == '%') {
    f.out.write_char('%');
    f.cursor++;
  }
  else {
    Spec spec = f.spec();
    f.print(spec, f.take($format.reason.missing_value()));
  }
  f.literal = f.cursor;
}

static void Format.write_literal(Format &f) {
  f.out.write_len(f.fmt + f.literal, (size_t) (f.cursor - f.literal));
}

/* A conversion that reaches the end of the format is incomplete. */
static void Format.need_byte(Format &f) {
  if (f.cursor == f.length) f.fail($format.reason.incomplete());
}

// conversion specifications

/* Parses the flags, width, precision, length modifier, and conversion
   after `%`, then rejects what the checked subset leaves out. */
static Spec Format.spec(Format &f) {
  Spec spec = {.flags = f.flags(), .precision = -1};
  f.width(spec);
  f.precision(spec);
  f.need_byte();
  spec.modifier = f.modifier();
  f.need_byte();
  spec.conversion = f.fmt[f.cursor++];
  f.check(spec);
  return spec;
}

static int Format.flags(Format &f) {
  int flags = 0;
  for (const char *flag; (flag = strchr(_format_flags, f.byte()));) {
    flags |= 1 << (flag - _format_flags);
    f.cursor++;
    f.need_byte();
  }
  return flags;
}

/* A `*` width takes the next value, and a negative one also sets `-`. */
static void Format.width(Format &f, Spec &spec) {
  if (f.byte() == '*') {
    int width = f.star();
    if (width == INT_MIN) f.fail($format.reason.width_range());
    if (width < 0) spec.flags |= FORMAT_LEFT;
    spec.width = abs(width);
    f.cursor++;
  }
  else spec.width = f.decimal("width");
}

/* A `*` width or precision is the next value as an int. */
static int Format.star(Format &f) =>
  (int) f.number(f.take($format.reason.missing_star()), <i32>).integer();

/* A `*` precision takes the next value, and a negative one means none. */
static void Format.precision(Format &f, Spec &spec) {
  if (f.byte() != '.') return;
  f.cursor++;
  f.need_byte();
  if (f.byte() == '*') {
    spec.precision = f.star();
    f.cursor++;
  }
  else spec.precision = f.decimal("precision");
}

/* Reads the digits at the cursor. An overflow reports the offset of the
   first digit and names the field with `label`. */
static int Format.decimal(Format &f, String label) {
  int number = 0, start = f.cursor;
  while (f.digit()) {
    int digit = f.byte() - '0';
    if (number > (INT_MAX - digit) / 10)
      _format_error(start, $format.reason.range(label));
    number = number * 10 + digit;
    f.cursor++;
  }
  return number;
}

static int Format.byte(Format &f) => f.fmt[f.cursor];

static int Format.digit(Format &f) => f.byte() >= '0' && f.byte() <= '9';

static int Format.modifier(Format &f) {
  switch (f.byte()) {
    case 'h': return f.doubled('h', FORMAT_H, FORMAT_HH);
    case 'l': return f.doubled('l', FORMAT_L, FORMAT_LL);
    case 'L': f.cursor++; return FORMAT_CAP_L;
    case 'j': case 'z': case 't': f.fail($format.reason.length());
  }
  return 0;
}

/* `h` or `hh`, and `l` or `ll`. */
static int Format.doubled(Format &f, char letter, int once, int twice) {
  f.cursor++;
  if (f.byte() != letter) return once;
  f.cursor++;
  return twice;
}

/* Rejects the conversions and combinations the checked subset leaves out,
   in this order. */
static void Format.check(Format &f, Spec spec) {
  char ch = spec.conversion;
  int integer = strchr("diouxX", ch) != NULL;
  int floating = strchr("fFeEgGaA", ch) != NULL, text = ch == 'c' || ch == 's';
  if (ch == '$') f.fail($format.reason.positional());
  if (!integer && !floating && !text) f.fail($format.reason.conversion());
  if (integer && spec.modifier == FORMAT_CAP_L)
    f.fail($format.reason.integer_length());
  if (floating && spec.modifier && spec.modifier != FORMAT_L &&
      spec.modifier != FORMAT_CAP_L)
    f.fail($format.reason.floating_length());
  if (text && spec.modifier)
    f.fail($format.reason.wide_text());
  if (text && (spec.flags & ~FORMAT_LEFT))
    f.fail($format.reason.flag());
  if (ch == 'c' && spec.precision >= 0)
    f.fail($format.reason.character_precision());
}

// conversion arguments

/* The next argument, or a failure with `reason` when none is left. */
static Var Format.take(Format &f, String reason) {
  if (!f.args) f.fail(reason);
  Var arg = f.args.car();
  f.args = f.args.cdr();
  return arg;
}

/* Prints `arg` through the C spelling of `spec`. The check leaves only
   these conversions, so the floating ones are the rest. */
static Buffer Format.print(Format &f, Spec spec, Var arg) {
  if (strchr("diouxX", spec.conversion)) return f.integer(spec, arg);
  char text[48];
  spec.spell(text);
  switch (spec.conversion) {
    case 'c': return f.character(text, arg);
    case 's': return f.string(text, arg);
  }
  return f.floating(text, spec.modifier, arg);
}

/* Writes the C spelling of `s`, with `*` values as numbers. */
static void Spec.spell(Spec s, char *out) {
  int n = 0;
  out[n++] = '%';
  for (int bit = 0; _format_flags[bit]; bit++)
    if (s.flags & 1 << bit) out[n++] = _format_flags[bit];
  if (s.width) n += snprintf(out + n, 16, "%d", s.width);
  if (s.precision >= 0) n += snprintf(out + n, 16, ".%d", s.precision);
  snprintf(out + n, 8, "%s%c", _format_modifiers[s.modifier], s.conversion);
}

// The type each modifier converts an integer to, signed then unsigned.
static const Symbol _integer_targets[][2] = {
  {<i32>, <u32>}, {<i8>, <u8>}, {<i16>, <u16>}, {<long>, <ulong>},
  {<llong>, <ullong>}
};

/* An integer is converted to its modifier's type, then printed as a long
   long, which prints every narrower value as its own modifier would. */
static Buffer Format.integer(Format &f, Spec spec, Var arg) {
  int is_unsigned = strchr("ouxX", spec.conversion) != NULL;
  Var value = f.number(arg, _integer_targets[spec.modifier][is_unsigned]);
  char text[48];
  spec.modifier = FORMAT_LL;
  spec.spell(text);
  if (is_unsigned) return f.out.printf(text, value.ulong_long());
  return f.out.printf(text, value.long_long());
}

/* `L` prints a long double, and the other modifiers a double. */
static Buffer Format.floating(
  Format &f, const char *text, int modifier, Var arg) {
  if (modifier == FORMAT_CAP_L)
    return f.out.printf(text, f.number(arg, <ldouble>).long_double_value());
  return f.out.printf(text, f.number(arg, <f64>).floating());
}

static Buffer Format.character(Format &f, const char *text, Var arg) {
  int byte = (int) f.number(arg, <i32>).integer();
  if (!(unsigned char) byte) f.fail($format.reason.character_nul());
  return f.out.printf(text, byte);
}

/* Prints the display text of `arg`, nesting a failure's cause. */
static Buffer Format.string(Format &f, const char *text, Var arg) {
  String string = NULL;
  try string = arg.str();
  catch %(?code *details):
    f.nested($format.reason.string(), code, details);
  return f.out.printf(text, string ? string : "");
}

/* Converts `arg` to the numeric `target`, nesting a failure's cause. */
static Var Format.number(Format &f, Var arg, Symbol target) {
  Var converted = void;
  try converted = arg.convert(target);
  catch %(?code *details):
    f.nested($format.reason.value(), code, details);
  return converted;
}

// errors

static void _format_error(int offset, String reason) {
  raise %(format (offset $offset) (reason $reason));
}

static void Format.fail(Format &f, String reason) {
  _format_error(f.offset, reason);
}

/* Raises `<format>` for the current conversion with the cause of a failed
   conversion nested. */
static void Format.nested(Format &f, String reason, Var code, List details) {
  List cause = cons(code, details);
  raise %(format (offset ${f.offset}) (reason $reason) (cause $cause));
}
