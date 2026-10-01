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

// representation

/* One conversion specification: the flag bits, the width and precision with
   their presence, a length modifier, and the conversion byte. */
typedef struct Spec {
  int flags, width, precision, has_width, has_precision, modifier;
  char conversion;
} Spec;

// The flag bits of `-+ #0`, in that order.
enum {
  FORMAT_LEFT = 1, FORMAT_PLUS = 2, FORMAT_SPACE = 4, FORMAT_ALT = 8,
  FORMAT_ZERO = 16
};

// The length modifiers `hh h l ll L`; zero is none.
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
  if (!fmt || !*fmt) {
    if (values) _format_error(0, "excess values");
    return NULL;
  }
  Buffer out = $auto(Buffer.new(0));
  Format f = {.fmt = fmt, .length = fmt.len(), .args = values, .out = out};
  while (f.cursor < f.length)
    if (f.byte() == '%') f.conversion();
    else f.cursor++;
  f.write_literal();
  if (f.args) _format_error(f.length, "excess values");
  return out;
}

/* Writes the text before the `%` at the cursor, then the conversion that
   `%` starts. */
static void Format.conversion(Format *f) {
  f.write_literal();
  f.offset = f.cursor++;
  f.need_byte();
  if (f.byte() == '%') {
    f.out.write_char('%');
    f.cursor++;
  }
  else {
    Spec spec = f.spec();
    f.print(spec, f.take("missing value"));
  }
  f.literal = f.cursor;
}

static void Format.write_literal(Format *f) {
  f.out.write_len(f.fmt + f.literal, (size_t) (f.cursor - f.literal));
}

/* A conversion that reaches the end of the format is incomplete. */
static void Format.need_byte(Format *f) {
  if (f.cursor == f.length) f.fail("incomplete conversion");
}

// conversion specifications

/* Parses the flags, width, precision, length modifier, and conversion
   after `%`, then rejects what the checked subset leaves out. */
static Spec Format.spec(Format *f) {
  Spec spec = {.flags = f.flags()};
  f.width(spec);
  f.precision(spec);
  f.need_byte();
  spec.modifier = f.modifier();
  f.need_byte();
  spec.conversion = f.fmt[f.cursor++];
  f.check(spec);
  return spec;
}

static int Format.flags(Format *f) {
  int flags = 0;
  for (;;) {
    switch (f.byte()) {
      case '-': flags |= FORMAT_LEFT; break;
      case '+': flags |= FORMAT_PLUS; break;
      case ' ': flags |= FORMAT_SPACE; break;
      case '#': flags |= FORMAT_ALT; break;
      case '0': flags |= FORMAT_ZERO; break;
      default: return flags;
    }
    f.cursor++;
    f.need_byte();
  }
}

/* A `*` width takes the next value, and a negative one also sets `-`. */
static void Format.width(Format *f, Spec &spec) {
  if (f.byte() == '*') {
    int width = f.star();
    if (width == INT_MIN) f.fail("width exceeds int range");
    if (width < 0) {
      spec.flags |= FORMAT_LEFT;
      width = -width;
    }
    spec.has_width = 1;
    spec.width = width;
    f.cursor++;
  }
  else if (f.digit()) {
    spec.has_width = 1;
    spec.width = f.decimal("width");
  }
}

/* A `*` width or precision is the next value as an int. */
static int Format.star(Format *f) =>
  (int) f.number(f.take("missing star value"), <i32>).integer();

/* A `*` precision takes the next value, and a negative one means none. */
static void Format.precision(Format *f, Spec &spec) {
  if (f.cursor >= f.length || f.byte() != '.') return;
  spec.has_precision = 1;
  f.cursor++;
  f.need_byte();
  if (f.byte() == '*') {
    int precision = f.star();
    if (precision < 0) spec.has_precision = 0;
    else spec.precision = precision;
    f.cursor++;
  }
  else if (f.digit()) spec.precision = f.decimal("precision");
}

/* Reads the digits at the cursor. An overflow reports the offset of the
   first digit and names the field with `label`. */
static int Format.decimal(Format *f, String label) {
  int number = 0, start = f.cursor;
  while (f.cursor < f.length && f.digit()) {
    int digit = f.byte() - '0';
    if (number > (INT_MAX - digit) / 10)
      _format_error(start, %"$label exceeds int range");
    number = number * 10 + digit;
    f.cursor++;
  }
  return number;
}

static int Format.byte(Format *f) => f.fmt[f.cursor];

static int Format.digit(Format *f) => f.byte() >= '0' && f.byte() <= '9';

static int Format.modifier(Format *f) {
  switch (f.byte()) {
    case 'h': return f.doubled('h', FORMAT_H, FORMAT_HH);
    case 'l': return f.doubled('l', FORMAT_L, FORMAT_LL);
    case 'L': f.cursor++; return FORMAT_CAP_L;
    case 'j': case 'z': case 't': f.fail("unsupported length modifier");
  }
  return 0;
}

/* `h` or `hh`, and `l` or `ll`. */
static int Format.doubled(Format *f, char letter, int once, int twice) {
  f.cursor++;
  if (f.cursor >= f.length || f.byte() != letter) return once;
  f.cursor++;
  return twice;
}

/* Rejects the conversions and combinations the checked subset leaves out,
   in this order. */
static void Format.check(Format *f, Spec spec) {
  char ch = spec.conversion;
  int integer = strchr("diouxX", ch) != NULL;
  int floating = strchr("fFeEgGaA", ch) != NULL, text = ch == 'c' || ch == 's';
  if (ch == '$') f.fail("positional formats are unsupported");
  if (!integer && !floating && !text) f.fail("unsupported conversion");
  if (integer && spec.modifier == FORMAT_CAP_L)
    f.fail("unsupported integer length");
  if (floating && spec.modifier && spec.modifier != FORMAT_L &&
      spec.modifier != FORMAT_CAP_L)
    f.fail("unsupported floating length");
  if (text && spec.modifier)
    f.fail("wide strings and characters are unsupported");
  if (text && (spec.flags & ~FORMAT_LEFT))
    f.fail("unsupported flag for conversion");
  if (ch == 'c' && spec.has_precision) f.fail("unsupported precision for %c");
}

// conversion arguments

/* The next argument, or a failure with `reason` when none is left. */
static Var Format.take(Format *f, String reason) {
  if (!f.args) f.fail(reason);
  Var arg = f.args.car();
  f.args = f.args.cdr();
  return arg;
}

/* Prints `arg` through the C spelling of `spec`. The check leaves only
   these conversions, so the floating ones are the rest. */
static Buffer Format.print(Format *f, Spec spec, Var arg) {
  char text[48];
  spec.spell(text);
  switch (spec.conversion) {
    case 'd': case 'i': return f.signed_int(text, spec.modifier, arg);
    case 'o': case 'u': case 'x': case 'X':
      return f.unsigned_int(text, spec.modifier, arg);
    case 'c': return f.character(text, arg);
    case 's': return f.string(text, arg);
  }
  return f.floating(text, spec.modifier, arg);
}

/* Writes the C spelling of `s`, with `*` values as numbers. */
static void Spec.spell(Spec s, char *out) {
  int n = 0;
  out[n++] = '%';
  if (s.flags & FORMAT_LEFT) out[n++] = '-';
  if (s.flags & FORMAT_PLUS) out[n++] = '+';
  if (s.flags & FORMAT_SPACE) out[n++] = ' ';
  if (s.flags & FORMAT_ALT) out[n++] = '#';
  if (s.flags & FORMAT_ZERO) out[n++] = '0';
  if (s.has_width && s.width) n += snprintf(out + n, 16, "%d", s.width);
  if (s.has_precision) {
    out[n++] = '.';
    n += snprintf(out + n, 16, "%d", s.precision);
  }
  switch (s.modifier) {
    case FORMAT_HH: out[n++] = 'h'; out[n++] = 'h'; break;
    case FORMAT_H: out[n++] = 'h'; break;
    case FORMAT_L: out[n++] = 'l'; break;
    case FORMAT_LL: out[n++] = 'l'; out[n++] = 'l'; break;
    case FORMAT_CAP_L: out[n++] = 'L'; break;
  }
  out[n++] = s.conversion;
  out[n] = '\0';
}

/* Integer conversions print a long or a long long for `l` and `ll`, and
   otherwise an int or unsigned holding the value at the modifier's width. */
static Buffer Format.signed_int(
  Format *f, const char *text, int modifier, Var arg) {
  switch (modifier) {
    case FORMAT_L:
      return f.out.printf(text, f.number(arg, <long>).long_value());
    case FORMAT_LL:
      return f.out.printf(text, f.number(arg, <llong>).long_long_value());
  }
  return f.out.printf(text, f.narrow_signed(arg, modifier));
}

static int Format.narrow_signed(Format *f, Var arg, int modifier) {
  switch (modifier) {
    case FORMAT_HH: return (signed char) f.number(arg, <i8>).integer();
    case FORMAT_H: return (short) f.number(arg, <i16>).integer();
  }
  return (int) f.number(arg, <i32>).integer();
}

static Buffer Format.unsigned_int(
  Format *f, const char *text, int modifier, Var arg) {
  switch (modifier) {
    case FORMAT_L:
      return f.out.printf(text, f.number(arg, <ulong>).ulong_value());
    case FORMAT_LL:
      return f.out.printf(text, f.number(arg, <ullong>).ulong_long_value());
  }
  return f.out.printf(text, f.narrow_unsigned(arg, modifier));
}

static unsigned Format.narrow_unsigned(Format *f, Var arg, int modifier) {
  switch (modifier) {
    case FORMAT_HH: return (unsigned char) f.number(arg, <u8>).integer();
    case FORMAT_H: return (unsigned short) f.number(arg, <u16>).integer();
  }
  return (unsigned int) f.number(arg, <u32>).integer();
}

/* `L` prints a long double, and the other modifiers a double. */
static Buffer Format.floating(
  Format *f, const char *text, int modifier, Var arg) {
  if (modifier == FORMAT_CAP_L)
    return f.out.printf(text, f.number(arg, <ldouble>).long_double_value());
  return f.out.printf(text, f.number(arg, <f64>).floating());
}

static Buffer Format.character(Format *f, const char *text, Var arg) {
  int byte = (int) f.number(arg, <i32>).integer();
  if (!(unsigned char) byte) f.fail("%c cannot produce an embedded NUL");
  return f.out.printf(text, byte);
}

static Buffer Format.string(Format *f, const char *text, Var arg) {
  String string = f.text(arg);
  return f.out.printf(text, string ? string : "");
}

/* Converts `arg` to the numeric `target`, nesting a failure's cause. */
static Var Format.number(Format *f, Var arg, Symbol target) {
  Var converted = void;
  try converted = arg.convert(target);
  catch %(?code *details): f.nested("value conversion failed", code, details);
  return converted;
}

/* The display text of `arg`, nesting a failure's cause. */
static String Format.text(Format *f, Var arg) {
  String converted = NULL;
  try converted = arg.str();
  catch %(?code *details): f.nested("string conversion failed", code, details);
  return converted;
}

// errors

static void _format_error(int offset, String reason) {
  raise %(format (offset $offset) (reason $reason));
}

static void Format.fail(Format *f, String reason) {
  _format_error(f.offset, reason);
}

/* Raises `<format>` for the current conversion with the cause of a failed
   conversion nested. */
static void Format.nested(Format *f, String reason, Var code, List details) {
  List cause = cons(code, details);
  raise %(format (offset ${f.offset}) (reason $reason) (cause $cause));
}
