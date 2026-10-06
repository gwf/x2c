/*  varconvert.x -- `Var` numeric conversion policy

    Converts among `Var`'s fifteen numeric families. Integer conversions keep
    the target width's low bits; floating-to-integer conversions truncate
    toward zero and require a representable result. A nonnumeric value
    converts only to its own tag.
*/

#pragma once

#include "error-macros.x"
#include "common.x"

/** Describes one numeric `Var` family without holding a value.
    `tag` is canonical, `floating` and `unsigned_value` classify it, `bits` is
    its native payload width, and `rank` orders promotion. Callers normally
    obtain a valid record from `Var.numeric_info`.
*/
typedef struct X2CVarNumericInfo {
  Symbol tag, int floating, unsigned_value, bits, rank;
} X2CVarNumericInfo;

/** Holds a decoded numeric `Var` and its promotion metadata.
    Integer values use the low `bits` of `raw`, with signed values represented
    in two's-complement; floating values use `floating_value`. The record
    holds no storage and retains nothing from the source `Var`.
*/
typedef struct X2CVarNumeric {
  Symbol tag, int floating, unsigned_value, bits, rank;
  unsigned long long raw;
  long double floating_value;
} X2CVarNumeric;

float X2CVarNumeric.f32(X2CVarNumeric &value);
double X2CVarNumeric.f64(X2CVarNumeric &value);
long double X2CVarNumeric.ldouble(X2CVarNumeric &value);


#include "meta.x"

/* Var numeric conversion error conditions.
   Reports expand at their existing owners. */

static macro Stmt $error.encoding.bad(Expr $bits) {
  raise %(bad-enc (value ${$bits}));
}

static macro Stmt $error.convert.void() {
  raise %(void-op (operation "Var.convert"));
}

static macro Stmt $error.target.invalid(Expr $target) {
  raise %(bad-target (target ${$target}));
}

static macro Stmt $error.source.numeric(Expr $source_tag, Expr $target) {
  using $lower;
  {
    List $lower = %(bad-types (source ${$source_tag}));
    raise %(no-convert (target ${$target}) (cause ${$lower}));
  }
}

static macro Stmt $error.target.numeric(Expr $source_tag, Expr $target) {
  raise %(no-convert (source ${$source_tag}) (target ${$target}));
}

static macro Stmt $error.decode.output() {
  raise %(bad-arg (operation "Var.numeric_decode"));
}

static macro Stmt $error.decode.void() {
  raise %(void-op (operation "Var.numeric_decode"));
}

static macro Stmt $error.decode.type(Expr $tag) {
  raise %(bad-types (source ${$tag}));
}

static macro Stmt $error.convert.range(Expr $source_tag, Expr $target) {
  raise %(conv-range (source ${$source_tag}) (target ${$target}));
}


#include "var.x"
#include "error.x"
#include "list.x"
#include "string.x"
#include "symbol.x"
#include "symbolset.x"

#include <limits.h>
#include <math.h>
#include <string.h>

/* `lib/var-ledger.x` projects both tables from the tag ledger's numeric rows
   in the same order, so the SymbolSet index is the metadata-table index.
   Promotion and conversion read widths and ranks from these rows. */
extern const SymbolSet x2c_var_numeric_tags;
extern const X2CVarNumericInfo x2c_var_numerics[];

// conversion

/** Converts `value` to a numeric `target`, or returns exact-tag identity.
    All fifteen numeric families cross through the rules in this module.
    Integer narrowing keeps low bits, floating-to-integer truncates toward
    zero with a range check, and floating results follow host conversion.
    Identity returns the original `Var` and preserves its ownership; a newly
    boxed wide numeric result belongs to the active `Scope`. Converting a
    discrete `<nan>`, `<-inf>`, or `<+inf>` value to `<f64>` also returns the
    original `Var`, preserving its discrete tag.

    Raises: `<bad-enc>` for invalid `Var` bits, `<void-op>` for `void`,
    `<bad-target>` for an unsupported target, `<no-convert>` for a nonnumeric
    source, `<conv-range>` when the result does not fit, or `<alloc-fail>`
    while boxing a wide result. A nonnumeric source is rejected before
    decoding, with the decoder's `<bad-types>` detail nested under
    `<no-convert>`. */
meta native Var Var.convert(Var value, Symbol target) {
  if (!value.encoding_valid()) {
    unsigned long bits = value.u64;
    $error.encoding.bad(bits);
  }
  if (value is void) $error.convert.void();
  if (!target || !Var.known_tag(target) || target == <void> ||
      target == <nan> || target == <-inf> || target == <+inf>)
    $error.target.invalid(target);
  Symbol source_tag = value.tag();
  if (source_tag == target) return value;
  if ((source_tag == <nan> || source_tag == <-inf> ||
       source_tag == <+inf>) && target == <f64>)
    return value;
  X2CVarNumericInfo info;
  if (!Var.numeric_info(source_tag, info))
    $error.source.numeric(source_tag, target);
  X2CVarNumeric source;
  _numeric_decode(value, info, source);
  if (!Var.numeric_info(target, info))
    $error.target.numeric(source_tag, target);
  return info.floating
       ? _convert_to_float(source, target)
       : _convert_to_integer(source, target, info.unsigned_value, info.bits);
}

/** Writes numeric-family metadata for `tag` and returns nonzero.
    The special `<nan>`, `<-inf>`, and `<+inf>` tags report the `<f64>` family.
    A null `out` or nonnumeric tag returns zero and leaves storage untouched.
*/
int Var.numeric_info(Symbol tag, X2CVarNumericInfo &?out) {
  if (!out) return 0;
  if (tag == <nan> || tag == <-inf> || tag == <+inf>) tag = <f64>;
  int row = x2c_var_numeric_tags.index(tag);
  if (row < 0) return 0;
  out = x2c_var_numerics[row];
  return 1;
}

/** Decodes a numeric `value` into caller-owned `out` storage.
    The result retains no pointer into `value`; integer and floating payloads
    use the members described by `X2CVarNumeric`.
    Raises: `<bad-arg>` for a null output, `<bad-enc>` for invalid `Var` bits,
    `<void-op>` for `void`, or `<bad-types>` for a nonnumeric tag. These
    failures leave `out` unchanged.
*/
void Var.numeric_decode(Var value, X2CVarNumeric &?out) {
  if (!out) $error.decode.output();
  if (!value.encoding_valid()) {
    unsigned long bits = value.u64;
    $error.encoding.bad(bits);
  }
  if (value is void) $error.decode.void();
  X2CVarNumericInfo info;
  Symbol tag = value.tag();
  if (!Var.numeric_info(tag, info)) $error.decode.type(tag);
  _numeric_decode(value, info, out);
}

/* Both callers establish valid numeric encoding and family metadata before
   payload extraction; the public decoder still owns its argument checks.
   One switch covers all fifteen families. Split by the floating flag, the
   switch let clang compute the `<f64>` special cases for every float. */
static void _numeric_decode(
  Var value, X2CVarNumericInfo info, X2CVarNumeric &out) {
  X2CVarNumeric decoded = {
    .tag = info.tag, .floating = info.floating,
    .unsigned_value = info.unsigned_value, .bits = info.bits,
    .rank = info.rank};
  with decoded {
    switch (info.tag) {
      case <i8>: case <u8>: case <i16>: case <u16>: case <i32>: case <u32>:
        _.raw = value.payload32() & Var.width_mask(_.bits); break;
      case <i48>: case <u48>: _.raw = value.u64 & Var.width_mask(48); break;
      case <long>:  _.raw = (unsigned long long) value.long_value(); break;
      case <ulong>: _.raw = (unsigned long long) value.ulong_value(); break;
      case <llong>:
        _.raw = (unsigned long long) value.long_long_value(); break;
      case <ullong>: _.raw = value.ulong_long_value(); break;
      case <f32>: _.floating_value = (long double) value.decode_f32(); break;
      case <f64>: _.floating_value = (long double) value.decode_f64(); break;
      case <ldouble>: _.floating_value = value.long_double_value(); break;
    }
  }
  out = decoded;
}

// integer targets

/* Integer-to-integer never passes through floating point; it narrows modulo
   the target width. Only floating-to-integer is range checked, and only
   after truncation. */
static Var _convert_to_integer(
  X2CVarNumeric &source, Symbol target, int unsigned_target, int bits) {
  if (!source.floating) {
    unsigned long long raw = source.unsigned_value ? source.raw
                           : (unsigned long long)
                             Var.signed_from_bits(source.raw, source.bits);
    return Var.integer_box(target, raw);
  }
  long double truncated = truncl(source.floating_value);
  if (!isfinite(source.floating_value)) _out_of_range(source, target);
  if (unsigned_target) {
    if (truncated < 0.0L || truncated >= _integer_limit(bits))
      _out_of_range(source, target);
    return Var.integer_box(target, (unsigned long long) truncated);
  }
  long double limit = _integer_limit(bits - 1);
  if (truncated < -limit || truncated >= limit) _out_of_range(source, target);
  return Var.integer_box(target, (unsigned long long) (long long) truncated);
}

static void _out_of_range(X2CVarNumeric &source, Symbol target) {
  Symbol source_tag = source.tag;
  $error.convert.range(source_tag, target);
}

static long double _integer_limit(int bits) {
  if (bits == 64) return (long double) (1ull << 63) * 2.0L;
  return (long double) (1ull << bits);
}

/** Boxes the low target-width bits of `raw` using integer `target`.
    Signed targets interpret those bits as two's-complement. Immediate targets
    return self-contained values; wide targets allocate their boxes in the
    active `Scope`.
    Raises: `<bad-target>` for a noninteger target, or `<alloc-fail>` or
    `<bad-enc>` while boxing a wide result.
*/
Var Var.integer_box(Symbol target, unsigned long long raw) {
  X2CVarNumericInfo info;
  if (!Var.numeric_info(target, info) || info.floating)
    $error.target.invalid(target);
  raw &= Var.width_mask(info.bits);
  long long signed_value = Var.signed_from_bits(raw, info.bits);
  switch (target) {
    case <i8>:     return Var.box_i8((char) signed_value);
    case <u8>:     return Var.box_u8((uchar) raw);
    case <i16>:    return Var.box_i16((short) signed_value);
    case <u16>:    return Var.box_u16((ushort) raw);
    case <i32>:    return Var.box_i32_bits((unsigned) raw);
    case <u32>:    return Var.box_u32((unsigned) raw);
    case <i48>:    return Var.new(<i48>, (long) signed_value);
    case <u48>:    return Var.new(<u48>, (unsigned long) raw);
    case <long>:   return Var.box_long((long) signed_value);
    case <ulong>:  return Var.box_ulong((unsigned long) raw);
    case <llong>:  return Var.box_long_long(signed_value);
    case <ullong>: return Var.box_ulong_long(raw);
  }
  $error.target.invalid(target);
}

/** Returns the integer tag selected by `rank` and signedness.
    `rank` must be positive. Ranks one through three map to `<i32>` or `<u32>`;
    callers applying integer promotion must first select its resulting
    signedness. Ranks four through six select the 48-bit, `long`, and
    `long long` families. A rank above six returns the null `Symbol`.
*/
Symbol Var.integer_tag(int rank, int unsigned_value) {
  if (rank <= 3) return unsigned_value ? <u32> : <i32>;
  if (rank == 4) return unsigned_value ? <u48> : <i48>;
  if (rank == 5) return unsigned_value ? <ulong> : <long>;
  if (rank == 6) return unsigned_value ? <ullong> : <llong>;
  return 0;
}

/** Returns a mask containing the low `bits` bits.
    Zero yields zero and a width at least `unsigned long long` yields
    `ULLONG_MAX`; `bits` must not be negative.
*/
unsigned long long Var.width_mask(int bits) =>
  bits >= (int) (sizeof(unsigned long long) * CHAR_BIT)
       ? ULLONG_MAX : (1ull << bits) - 1ull;

/** Interprets the low `bits` of `raw` as a two's-complement signed value.
    `bits` must be between one and the width of `unsigned long long`.
*/
long long Var.signed_from_bits(unsigned long long raw, int bits) {
  if (bits < (int) (sizeof(unsigned long long) * CHAR_BIT)) {
    unsigned long long mask = Var.width_mask(bits), sign = 1ull << (bits - 1);
    raw &= mask;
    if (raw & sign) return -(long long) ((~raw & mask) + 1ull);
    return (long long) raw;
  }
  long long value;
  memcpy(&value, &raw, sizeof value);
  return value;
}

// floating targets

/* Floating results use host casts, so a wide target gets a new Scope box. */
static Var _convert_to_float(X2CVarNumeric &source, Symbol target) {
  switch (target) {
    case <f32>: return Var.box_f32(source.f32());
    case <f64>: return Var.box_f64(source.f64());
    case <ldouble>: return Var.box_long_double(source.ldouble());
    default: $error.target.invalid(target);
  }
}

/** Converts a decoded numeric value to native `float` without boxing.
    Uses the target host cast, preserving its rounding behavior.
*/
float X2CVarNumeric.f32(X2CVarNumeric &value) {
  if (value.floating) return (float) value.floating_value;
  if (value.unsigned_value) return (float) value.raw;
  return (float) Var.signed_from_bits(value.raw, value.bits);
}

/** Converts a decoded numeric value to native `double` without boxing.
    Uses the target host cast, preserving its rounding behavior.
*/
double X2CVarNumeric.f64(X2CVarNumeric &value) {
  if (value.floating) return (double) value.floating_value;
  if (value.unsigned_value) return (double) value.raw;
  return (double) Var.signed_from_bits(value.raw, value.bits);
}

/** Converts a decoded numeric value to native `long double` without boxing.
    Uses the target host cast, preserving its rounding behavior.
*/
long double X2CVarNumeric.ldouble(X2CVarNumeric &value) {
  if (value.floating) return value.floating_value;
  if (value.unsigned_value) return (long double) value.raw;
  return (long double) Var.signed_from_bits(value.raw, value.bits);
}
