/*  ordering.x -- integer and mixed numeric comparisons */

// ordering

static typedef struct VarIntegerParts {
  int negative, unsigned long long magnitude;
} VarIntegerParts;

/** Orders the integer payloads of `a` and `b`, returning -1, 0, or 1.
    Each value is decomposed into a sign and an unsigned magnitude first, so
    the whole integer range orders correctly, including a `<ullong>` above
    `LONG_MAX` against a negative `<long>`. Subtracting in a fixed-width
    integer type could overflow.

    Both arguments are assumed to be integer-kinded. Another value is decoded
    by `Var.integer`, which reads it as 0. Confirm with `Var.is_integer` when
    the kinds are not known.
*/
int Var.integer_compare(Var a, Var b) {
  VarIntegerParts ap = _integer_parts(a), bp = _integer_parts(b);
  if (ap.negative != bp.negative) return ap.negative ? -1 : 1;
  if (ap.magnitude == bp.magnitude) return 0;
  if (ap.negative) return ap.magnitude > bp.magnitude ? -1 : 1;
  return ap.magnitude < bp.magnitude ? -1 : 1;
}

static VarIntegerParts _integer_parts(Var v) {
  switch (v.tag()) {
    case <u8>: case <u16>: case <u32>: case <u48>:
      return _unsigned_parts((unsigned long long) v.integer());
    case <ulong>:  return _unsigned_parts(v.ulong_value());
    case <ullong>: return _unsigned_parts(v.ulong_long_value());
    case <long>:   return _signed_parts(v.long_value());
    case <llong>:  return _signed_parts(v.long_long_value());
  }
  return _signed_parts(v.integer());
}

static VarIntegerParts _unsigned_parts(unsigned long long magnitude) =>
  (VarIntegerParts) { 0, magnitude };

static VarIntegerParts _signed_parts(long long value) =>
  (VarIntegerParts) { value < 0, _signed_magnitude(value) };

static unsigned long long _signed_magnitude(long long value) {
  if (value >= 0) return (unsigned long long) value;
  return (unsigned long long) (-(value + 1)) + 1;
}

/** Orders an integer-kinded `integer` against a floating `floating`.
    Returns -1, 0, or 1 for less, equal, and greater. The integer is never
    converted to floating point, so a large `<ullong>` and a nearby `double`
    order by their true values. A floating value with a fractional part is
    never equal to an integer.

    `+Inf` is greater than every integer and `-Inf` is less than every
    integer. NaN is not ordered and reports -1. Test the tag for `<nan>`
    first if that distinction matters.
*/
int Var.integer_floating_compare(Var integer, Var floating) {
  VarIntegerParts parts = _integer_parts(integer);
  long double value = floating is <ldouble> ? floating.long_double_value()
                    : (long double) floating.floating();
  if (value != value || value == 1.0L / 0.0L) return -1;
  if (value == -1.0L / 0.0L) return 1;
  if (parts.negative) {
    if (value >= 0.0L) return -1;
    return -_magnitude_compare(parts.magnitude, -value);
  }
  if (value < 0.0L) return 1;
  return _magnitude_compare(parts.magnitude, value);
}

static int _magnitude_compare(
  unsigned long long integer, long double floating) {
  long double limit = (long double) (1ull << 63) * 2.0L;
  if (floating >= limit) return -1;
  unsigned long long floating_integer = (unsigned long long) floating;
  if (integer < floating_integer) return -1;
  if (integer > floating_integer) return 1;
  return floating == (long double) floating_integer ? 0 : -1;
}
