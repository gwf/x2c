/*  format.x -- checked formatting of `Var` values into a `String`

    Copyright (c) 2025 Gary William Flake

    `String.format` parses a checked subset of C's format syntax itself,
    converts each `Var` value to the C type its conversion names, and prints
    it through `Buffer.printf`, so a format read at run time cannot pass C a
    mismatched argument. `String.printf`, which hands C arguments straight
    to `vsnprintf`, stays with the other constructors in `string.x`.
*/


#include <limits.h>
#include <stdio.h>
#include <string.h>

#include "var/var.x"
#include "list/list.x"
#include "buffer.x"
#include "exception.x"

/* string-format diagnostic messages. Payload owners retain failure policy. */

static macro Expression $reason.excess_values() => "excess values";
static macro Expression $reason.missing_value() => "missing value";
static macro Expression $reason.incomplete() => "incomplete conversion";
static macro Expression $reason.width_range() => "width exceeds int range";
static macro Expression $reason.missing_star() => "missing star value";
static macro Expression $reason.length() => "unsupported length modifier";
static macro Expression $reason.positional() => "positional formats are unsupported";
static macro Expression $reason.conversion() => "unsupported conversion";
static macro Expression $reason.integer_length() => "unsupported integer length";
static macro Expression $reason.floating_length() => "unsupported floating length";
static macro Expression $reason.wide_text() =>
  "wide strings and characters are unsupported";
static macro Expression $reason.flag() => "unsupported flag for conversion";
static macro Expression $reason.character_precision() =>
  "unsupported precision for %c";
static macro Expression $reason.character_nul() =>
  "%c cannot produce an embedded NUL";
static macro Expression $reason.string() => "string conversion failed";
static macro Expression $reason.value() => "value conversion failed";
static macro Expression $reason.range(Expr $label) => %"${$label} exceeds int range";

// representation

/* One conversion specification: the flag bits, the width or zero for
   none, the precision or a negative value for none, a length modifier, and
   the conversion byte. */
static typedef struct Spec {
  int flags, width, precision, Symbol modifier;
  char conversion;
} Spec;

// A flag's bit is its position here, so `-` is `FORMAT_LEFT`.
static const char _format_flags[] = "-+ #0";
static enum { FORMAT_LEFT = 1 };

// The length modifiers and their native spellings in the same order.
static const SymbolSet format_modifiers =
  %<<none char short long llong ldouble>>;
static const char *const _format_modifiers[] = {"", "hh", "h", "l", "ll", "L"};

/* One pass of `String.format`. The bytes from `literal` to `cursor` are
   text not yet written, `offset` is the `%` of the conversion being read,
   which its errors report, and `args` holds the values still to take. */
static typedef struct Format {
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
    if (_byte(f) == '%') _conversion(f);
    else f.cursor++;
  _write_literal(f);
  if (f.args) _format_error(f.length, $reason.excess_values());
  return out;
}

/* Writes the text before the `%` at the cursor, then the conversion that
   `%` starts. */
static void _conversion(Format &f) {
  _write_literal(f);
  f.offset = f.cursor++;
  _need_byte(f);
  if (_byte(f) == '%') {
    f.out.write_char('%');
    f.cursor++;
  }
  else {
    Spec spec = _spec(f);
    _print(f, spec, _take(f, $reason.missing_value()));
  }
  f.literal = f.cursor;
}

static void _write_literal(Format &f) {
  if (f.cursor == f.literal) return;
  f.out.write_len(f.fmt + f.literal, (size_t) (f.cursor - f.literal));
}

/* A conversion that reaches the end of the format is incomplete. */
static void _need_byte(Format &f) {
  if (f.cursor == f.length) _fail(f, $reason.incomplete());
}

// conversion specifications

/* Parses the flags, width, precision, length modifier, and conversion
   after `%`, then rejects what the checked subset leaves out. */
static Spec _spec(Format &f) {
  Spec spec = {.flags = _flags(f), .precision = -1};
  _width(f, spec);
  _precision(f, spec);
  _need_byte(f);
  spec.modifier = _modifier(f);
  _need_byte(f);
  spec.conversion = f.fmt[f.cursor++];
  _check(f, spec);
  return spec;
}

static int _flags(Format &f) {
  int flags = 0;
  for (const char *flag; (flag = strchr(_format_flags, _byte(f)));) {
    flags |= 1 << (flag - _format_flags);
    f.cursor++;
    _need_byte(f);
  }
  return flags;
}

/* `*` consumes the next argument; a negative argument also sets `-`. */
static void _width(Format &f, Spec &spec) {
  if (_byte(f) == '*') {
    int width = _star(f);
    if (width == INT_MIN) _fail(f, $reason.width_range());
    if (width < 0) spec.flags |= FORMAT_LEFT;
    spec.width = abs(width);
    f.cursor++;
  }
  else spec.width = _decimal(f, "width");
}

/* A `*` width or precision is the next value as an int. */
static int _star(Format &f) =>
  (int) _number(f, _take(f, $reason.missing_star()), <i32>).integer();

/* `*` consumes the next argument; a negative argument means unspecified. */
static void _precision(Format &f, Spec &spec) {
  if (_byte(f) != '.') return;
  f.cursor++;
  _need_byte(f);
  if (_byte(f) == '*') {
    spec.precision = _star(f);
    f.cursor++;
  }
  else spec.precision = _decimal(f, "precision");
}

/* Reads the digits at the cursor. An overflow reports the offset of the
   first digit and names the field with `label`. */
static int _decimal(Format &f, String label) {
  int number = 0, start = f.cursor;
  while (_digit(f)) {
    int digit = _byte(f) - '0';
    if (number > (INT_MAX - digit) / 10)
      _format_error(start, $reason.range(label));
    number = number * 10 + digit;
    f.cursor++;
  }
  return number;
}

static int _byte(Format &f) => f.fmt[f.cursor];

static int _digit(Format &f) => _byte(f) >= '0' && _byte(f) <= '9';

static Symbol _modifier(Format &f) {
  switch (_byte(f)) {
    case 'h': return _doubled(f, 'h', <short>, <char>);
    case 'l': return _doubled(f, 'l', <long>, <llong>);
    case 'L': f.cursor++; return <ldouble>;
    case 'j': case 'z': case 't': _fail(f, $reason.length());
  }
  return <none>;
}

/* `h` or `hh`, and `l` or `ll`. */
static Symbol _doubled(Format &f, char letter, Symbol once, Symbol twice) {
  f.cursor++;
  if (_byte(f) != letter) return once;
  f.cursor++;
  return twice;
}

/* Rejects the conversions and combinations the checked subset leaves out,
   in this order. */
static void _check(Format &f, Spec spec) {
  char ch = spec.conversion;
  int integer = strchr("diouxX", ch) != NULL;
  int floating = strchr("fFeEgGaA", ch) != NULL, text = ch == 'c' || ch == 's';
  if (ch == '$') _fail(f, $reason.positional());
  if (!integer && !floating && !text) _fail(f, $reason.conversion());
  if (integer && spec.modifier == <ldouble>)
    _fail(f, $reason.integer_length());
  if (floating && spec.modifier != <none> && spec.modifier != <long> &&
      spec.modifier != <ldouble>)
    _fail(f, $reason.floating_length());
  if (text && spec.modifier != <none>)
    _fail(f, $reason.wide_text());
  if (text && (spec.flags & ~FORMAT_LEFT))
    _fail(f, $reason.flag());
  if (ch == 'c' && spec.precision >= 0)
    _fail(f, $reason.character_precision());
}

// conversion arguments

/* The next argument, or a failure with `reason` when none is left. */
static Var _take(Format &f, String reason) {
  if (!f.args) _fail(f, reason);
  Var arg = f.args.car();
  f.args = f.args.cdr();
  return arg;
}

/* Prints `arg` through the C spelling of `spec`. The check leaves only
   these conversions, so the floating ones are the rest. */
static Buffer _print(Format &f, Spec spec, Var arg) {
  if (strchr("diouxX", spec.conversion)) return _integer(f, spec, arg);
  char text[48];
  _spell(spec, text);
  switch (spec.conversion) {
    case 'c': return _character(f, text, arg);
    case 's': return _string(f, text, arg);
  }
  return _floating(f, text, spec.modifier, arg);
}

/* Writes the C spelling of `s`, with `*` values as numbers. */
static void _spell(Spec s, char *out) {
  int n = 0;
  out[n++] = '%';
  for (int bit = 0; _format_flags[bit]; bit++)
    if (s.flags & 1 << bit) out[n++] = _format_flags[bit];
  if (s.width) n += snprintf(out + n, 16, "%d", s.width);
  if (s.precision >= 0) n += snprintf(out + n, 16, ".%d", s.precision);
  snprintf(
    out + n, 8, "%s%c",
    _format_modifiers[format_modifiers.index(s.modifier)], s.conversion);
}

// The type each modifier converts an integer to, signed then unsigned.
static const Symbol _integer_targets[][2] = {
  {<i32>, <u32>}, {<i8>, <u8>}, {<i16>, <u16>}, {<long>, <ulong>},
  {<llong>, <ullong>}
};

/* An integer is converted to its modifier's type, then printed as a long
   long, which prints every narrower value as its own modifier would. */
static Buffer _integer(Format &f, Spec spec, Var arg) {
  int is_unsigned = strchr("ouxX", spec.conversion) != NULL;
  int modifier = format_modifiers.index(spec.modifier);
  Var value = _number(f, arg, _integer_targets[modifier][is_unsigned]);
  char text[48];
  spec.modifier = <llong>;
  _spell(spec, text);
  if (is_unsigned) return f.out.printf(text, value.ulong_long());
  return f.out.printf(text, value.long_long());
}

/* `L` prints a long double, and the other modifiers a double. */
static Buffer _floating(
  Format &f, const char *text, Symbol modifier, Var arg) {
  if (modifier == <ldouble>)
    return f.out.printf(text, _number(f, arg, <ldouble>).long_double_value());
  return f.out.printf(text, _number(f, arg, <f64>).floating());
}

static Buffer _character(Format &f, const char *text, Var arg) {
  int byte = (int) _number(f, arg, <i32>).integer();
  if (!(unsigned char) byte) _fail(f, $reason.character_nul());
  return f.out.printf(text, byte);
}

/* Prints the display text of `arg`, nesting a failure's cause. */
static Buffer _string(Format &f, const char *text, Var arg) {
  String string = NULL;
  try string = arg.str();
  catch %(?code *details):
    _nested(f, $reason.string(), code, details);
  return f.out.printf(text, string ? string : "");
}

/* Converts `arg` to the numeric `target`, nesting a failure's cause. */
static Var _number(Format &f, Var arg, Symbol target) {
  Var converted = void;
  try converted = arg.convert(target);
  catch %(?code *details):
    _nested(f, $reason.value(), code, details);
  return converted;
}

// errors

static void _format_error(int offset, String reason) {
  raise %(format (offset $offset) (reason $reason));
}

static void _fail(Format &f, String reason) {
  _format_error(f.offset, reason);
}

/* Raises `<format>` for the current conversion with the cause of a failed
   conversion nested. */
static void _nested(Format &f, String reason, Var code, List details) {
  List cause = cons(code, details);
  raise %(format (offset ${f.offset}) (reason $reason) (cause $cause));
}
