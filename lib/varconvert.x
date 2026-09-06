/*  varconvert.x -- `Var` numeric conversion policy

    Converts among `Var`'s fifteen numeric families. Integer conversions keep
    the target width's low bits; floating-to-integer conversions truncate
    toward zero and require a representable result. A nonnumeric
    value converts only to its own tag.
*/

#pragma once

$(import "error-macros.xmacro")
$(import "var-tags.xmacro")
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

/** Decodes a numeric `value` into caller-owned `out` storage.
    The result retains no pointer into `value`; integer and floating payloads
    use the members described by `X2CVarNumeric`.
    Raises: `<bad-arg>` for a null output, `<bad-enc>` for invalid `Var` bits,
    `<void-op>` for `void`, or `<bad-types>` for a nonnumeric tag. These
    failures leave `out` unchanged.
*/
void Var.numeric_decode(Var value, X2CVarNumeric *out) {
  if (!out) raise %(bad-arg (owner "Var.numeric_decode"));
  if (!Var.encoding_valid(value)) {
    unsigned long bits = value.u64;
    raise %(bad-enc (value $bits));
  }
  if (value is void) raise %(void-op (owner "Var.numeric_decode"));
  X2CVarNumeric decoded = { 0 }; X2CVarNumericInfo info;
  Symbol tag = value.tag();
  if (!Var.numeric_info(tag, &info)) raise %(bad-types (source $tag));
  with decoded {
    tag = _.tag = info.tag;
    _.floating = info.floating;
    _.unsigned_value = info.unsigned_value;
    _.bits = info.bits;
    _.rank = info.rank;
    switch (tag) {
      case <i8>: case <u8>: case <i16>: case <u16>: case <i32>: case <u32>:
        _.raw = Var.payload32(value) & Var.width_mask(_.bits); break;
      case <i48>: case <u48>:
        _.raw = value.u64 & Var.width_mask(48); break;
      case <long>: _.raw = (unsigned long long) value.long_value();  break;
      case <ulong>: _.raw = (unsigned long long) value.ulong_value();  break;
      case <llong>:
        _.raw = (unsigned long long) value.long_long_value(); break;
      case <ullong>: _.raw = value.ulong_long_value(); break;
      case <f32>:
        _.floating_value = (long double) Var.decode_f32(value); break;
      case <f64>:
        _.floating_value = (long double) Var.decode_f64(value); break;
      case <ldouble>: _.floating_value = value.long_double_value(); break;
    }
    *out = _;
  }
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
  if (!Var.numeric_info(target, &info) || info.floating)
    raise %(bad-target (target $target));
  raw &= Var.width_mask(info.bits);
  long long signed_value = Var.signed_from_bits(raw, info.bits);
  Var result;
  switch (target) {
    case <i8>:  result = Var.box_i8((char) signed_value); break;
    case <u8>:  result = Var.box_u8((uchar) raw); break;
    case <i16>: result = Var.box_i16((short) signed_value); break;
    case <u16>: result = Var.box_u16((ushort) raw); break;
    case <i32>: result = Var.box_i32_bits((unsigned) raw); break;
    case <u32>: result = Var.box_u32((unsigned) raw); break;
    case <i48>: result = Var.new(<i48>, (long) signed_value); break;
    case <u48>: result = Var.new(<u48>, (unsigned long) raw); break;
    case <long>: result = Var.box_long((long) signed_value); break;
    case <ulong>: result = Var.box_ulong((unsigned long) raw); break;
    case <llong>: result = Var.box_long_long((long long) signed_value); break;
    case <ullong>: result = Var.box_ulong_long(raw); break;
    default: raise %(bad-target (target $target));
  }
  return result;
}

#pragma private

#include "var.x"
#include "error.x"
#include "list.x"
#include "string.x"
#include "symbol.x"
#include "symbolset.x"

#include <limits.h>
#include <math.h>
#include <string.h>

/* Both projections walk the tag ledger's numeric rows in the same order, so
   the SymbolSet index is the metadata-table index. Promotion and conversion
   read widths and ranks from these rows. */
static const SymbolSet numeric_tags = $var.tag.numeric.symbolset();
static const X2CVarNumericInfo numerics[] = $var.tag.numeric();

/** Writes numeric-family metadata for `tag` and returns nonzero.
    The special `<nan>`, `<-inf>`, and `<+inf>` tags report the `<f64>` family.
    A null `out` or nonnumeric tag returns zero and leaves storage untouched.
*/
int Var.numeric_info(Symbol tag, X2CVarNumericInfo *out) {
  if (!out) return 0;
  if (tag == <nan> || tag == <-inf> || tag == <+inf>) tag = <f64>;
  int row = numeric_tags.index(tag);
  if (row < 0) return 0;
  *out = numerics[row];
  return 1;
}

static long double _integer_limit(int bits) {
  if (bits == 64) return (long double) (1ull << 63) * 2.0L;
  return (long double) (1ull << bits);
}

static float _numeric_f32(X2CVarNumeric *value) {
  if (value->floating) return (float) value->floating_value;
  if (value->unsigned_value) return (float) value->raw;
  return (float) Var.signed_from_bits(value->raw, value->bits);
}

static double _numeric_f64(X2CVarNumeric *value) {
  if (value->floating) return (double) value->floating_value;
  if (value->unsigned_value) return (double) value->raw;
  return (double) Var.signed_from_bits(value->raw, value->bits);
}

static long double _numeric_long_double(X2CVarNumeric *value) {
  if (value->floating) return value->floating_value;
  if (value->unsigned_value) return (long double) value->raw;
  return (long double) Var.signed_from_bits(value->raw, value->bits);
}

/* Conversion first decodes one source family. Integer-to-integer never passes
   through floating point; it narrows modulo the target width. Only
   floating-to-integer is range checked, and only after truncation. Float
   results use host casts, so a wide target gets a new Scope box. */
static Var _convert_to_integer(
  X2CVarNumeric *source, Symbol target, int unsigned_target, int bits) {
  unsigned long long raw;
  if (source->floating) {
    long double truncated = truncl(source->floating_value);
    if (!isfinite(source->floating_value)) {
      Symbol source_tag = source->tag;
      raise %(conv-range (source $source_tag) (target $target));
    }
    if (unsigned_target) {
      long double upper = _integer_limit(bits);
      if (truncated < 0.0L || truncated >= upper) {
        Symbol source_tag = source->tag;
        raise %(conv-range (source $source_tag) (target $target));
      }
      raw = (unsigned long long) truncated;
    }
    else {
      long double limit = _integer_limit(bits - 1);
      if (truncated < -limit || truncated >= limit) {
        Symbol source_tag = source->tag;
        raise %(conv-range (source $source_tag) (target $target));
      }
      long long signed_value = (long long) truncated;
      raw = (unsigned long long) signed_value;
    }
  }
  else
    raw = source->unsigned_value
        ? source->raw
        : (unsigned long long)
          Var.signed_from_bits(source->raw, source->bits);
  return Var.integer_box(target, raw);
}

static Var _convert_to_float(X2CVarNumeric *source, Symbol target) {
  switch (target) {
    case <f32>: return Var.box_f32(_numeric_f32(source));
    case <f64>: return Var.box_f64(_numeric_f64(source));
    case <ldouble>: return Var.box_long_double(_numeric_long_double(source));
    default: raise %(bad-target (target $target));
  }
}

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
Var Var.convert(Var value, Symbol target) {
  if (!Var.encoding_valid(value)) {
    unsigned long bits = value.u64;
    raise %(bad-enc (value $bits));
  }
  if (value is void) raise %(void-op (owner "Var.convert"));
  if (!target || !Var.known_tag(target) || target == <void> ||
      target == <nan> || target == <-inf> || target == <+inf>)
    raise %(bad-target (target $target));
  Symbol source_tag = value.tag();
  if (source_tag == target) return value;
  if ((source_tag == <nan> || source_tag == <-inf> ||
       source_tag == <+inf>) && target == <f64>)
    return value;
  X2CVarNumericInfo info;
  if (!Var.numeric_info(source_tag, &info)) {
    List lower = %(bad-types (source $source_tag));
    raise %(no-convert (target $target) (cause $lower));
  }
  X2CVarNumeric source;
  Var.numeric_decode(value, &source);
  if (!Var.numeric_info(target, &info))
    raise %(no-convert (source $source_tag) (target $target));
  return info.floating
       ? _convert_to_float(&source, target)
       : _convert_to_integer(&source, target, info.unsigned_value, info.bits);
}
