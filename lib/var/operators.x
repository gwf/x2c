/*  operators.x -- boxed `Var` operators, updates, and truthiness

    `Var` arithmetic applies C-style numeric promotion to runtime tags, wraps
    integer results to the selected type's width, and delegates eligible object
    operations through registered protocols. Comparisons of two numbers use
    the same promotion. Compound updates compute and convert completely before
    changing their destination.
*/

#include "error-macros.x"
#include "integer-ops.x"
#include "common.x"
#include "meta.x"

/* The entry's rows supply the storage boxer and decoder for each type;
   `_native_update` performs the operation and the conversion back. Native
   lvalues and direct Var compound updates use the same operation. */
static macro Unit $native.update(Type $type, Name $function, Literal $row) {
  using $converted;
  /** Applies a dynamic compound `op` to a native `$type` lvalue.
      The current value is boxed in its declared family, combined with `rhs`,
      converted back to that family, and stored only after all steps succeed.
      Returns the stored native value. This is failure-atomic but provides no
      thread synchronization despite accepting a volatile pointer.
      Raises: `<bad-arg>` for a null lvalue, or any cause from `Var.binary`,
      `Var.convert`, or wide boxing. A transferring failure leaves the lvalue
      unchanged. If a delegated protocol operation returns `void`, the helper
      also leaves it unchanged and returns the native zero for `$type`.
  */
  $type $function(
    volatile $type *$x2c_ident("lhs"), Symbol $x2c_ident("op"),
    Var $x2c_ident("rhs")) {
    if (!$x2c_ident("lhs"))
      raise %(bad-arg (operation $($_update_operation($function))));
    Var $converted = _native_update(
      $_update_box($row, $x2c_ident("lhs")),
      $_update_tag($row), $x2c_ident("op"), $x2c_ident("rhs"));
    if ($converted is void) return 0;
    $type value = $_update_decode($row, $converted);
    $x2c_ident("lhs")[0] = value;
    return value;
  }
}

$native.update(char, x2c_var_update_i8, <char>);
$native.update(signed char, x2c_var_update_schar, <schar>);
$native.update(uchar, x2c_var_update_u8, <u8>);
$native.update(short, x2c_var_update_i16, <i16>);
$native.update(ushort, x2c_var_update_u16, <u16>);
$native.update(int, x2c_var_update_i32, <i32>);
$native.update(uint, x2c_var_update_u32, <u32>);
$native.update(long, x2c_var_update_long, <long>);
$native.update(ulong, x2c_var_update_ulong, <ulong>);
$native.update(long long, x2c_var_update_long_long, <llong>);
$native.update(unsigned long long, x2c_var_update_ulong_long, <ullong>);
$native.update(float, x2c_var_update_f32, <f32>);
$native.update(double, x2c_var_update_f64, <f64>);
$native.update(long double, x2c_var_update_long_double, <ldouble>);

#include "var/var.x"
#include "dispatch.x"
#include "string/string.x"
#include "array/array.x"
#include "map/map.x"

$integer.raw(_integer_raw);

/* One arithmetic step in a floating family. Callers pass `+`, `-`, `*`, or
   `/`, so any other operator divides. */
static macro Unit $floating.step(Type $type, Name $name) {
  static $type $name(Symbol op, $type a, $type b) {
    switch (op) {
      case <+>: return a + b;
      case <->: return a - b;
      case <*>: return a * b;
    }
    return a / b;
  }
}

$floating.step(float, _f32_step);
$floating.step(double, _f64_step);
$floating.step(long double, _ldouble_step);

// operators

/** Applies a dynamic arithmetic, bitwise, comparison, or logical operator.
    Integers use C-style promotion and wrap to the result type's width;
    shifts use the promoted left operand's type and sign-fill signed right
    shifts. Floating arithmetic uses the widest floating-point operand type.
    Comparisons and identity tests give the operators' results on `Var`
    operands, so two numbers compare as their native values do in C.
    The logical operators are eager in this direct API. Equality and identity
    are the only operations that accept `void` and return an `<i32>` predicate.
    Immediate results are self-contained, canonical `String`s keep their pool
    lifetime, and newly boxed wide results belong to the active `Scope`.

    Raises: `<bad-enc>`, `<void-op>`, or `<bad-op>` at the dynamic boundary;
    numeric operations may additionally raise `<bad-types>`, `<div-zero>`,
    or `<bad-shift>`, and `String` concatenation or wide boxing may raise
    `<size-limit>`, `<alloc-fail>`, or `<bad-enc>`.
    A selected protocol, truth, or comparison callback may raise its own cause.
*/
Var Var.binary(Var lhs, Symbol op, Var rhs) {
  switch (op) {
    case <+>: return lhs.add(rhs);
    case <->: return lhs.sub(rhs);
    case <*>: return lhs.mul(rhs);
    case </>: return lhs.div(rhs);
    case <%>: return lhs.mod(rhs);
  }
  Var result = _fast_numeric(op, lhs, rhs);
  if (result.u64 != VAR_VOID_BITS) return result;
  _valid_operands(lhs, rhs);
  switch (op) {
    case <==>:  return Var.box_i32_bits((unsigned) (lhs == rhs));
    case <!=>:  return Var.box_i32_bits((unsigned) (lhs != rhs));
    case <===>: return Var.box_i32_bits((unsigned) (lhs === rhs));
    case <!==>: return Var.box_i32_bits((unsigned) (lhs !== rhs));
  }
  if (lhs is void || rhs is void) raise %(void-op (op $op));
  switch (op) {
    case <"<">:  return _predicate(lhs < rhs);
    case <"<=">: return _predicate(lhs <= rhs);
    case <">">:  return _predicate(lhs > rhs);
    case <">=">: return _predicate(lhs >= rhs);
    case <&&>: case <||>: return _predicate(_logical(lhs, op, rhs));
    case <&>: case <|>: case <^>: case <"<<">: case <">>">:
      return _general_numeric_binary(op, lhs, rhs);
  }
  raise %(bad-op (op $op));
}

/* Comparisons and _logical already return zero or one. */
static Var _predicate(int holds) => Var.box_i32_bits((unsigned) holds);

/* The direct API is eager: it reads both operands' truth, left first. */
static int _logical(Var lhs, Symbol op, Var rhs) {
  int left = !!lhs, right = !!rhs;
  return op == <&&> ? left && right : left || right;
}

/** Adds dynamic values through numeric, `String`, or registered `add`
    behavior.
    Numeric promotion, failure, and result ownership follow `Var.binary`;
    `String` addition returns a canonical concatenation, and a protocol result
    keeps the ownership chosen by its callback.
*/
meta native Var Var.add(Var lhs, Var rhs) =>
  _protocol_arithmetic(lhs, <add>, <+>, rhs);

/** Subtracts dynamic values through numeric or registered `sub` behavior.
    Numeric promotion, failure, and result ownership follow `Var.binary`; a
    protocol result keeps the ownership chosen by its callback.
*/
meta native Var Var.sub(Var lhs, Var rhs) =>
  _protocol_arithmetic(lhs, <sub>, <->, rhs);

/** Multiplies dynamic values through numeric or registered `mul` behavior.
    Numeric promotion, failure, and result ownership follow `Var.binary`; a
    protocol result keeps the ownership chosen by its callback.
*/
meta native Var Var.mul(Var lhs, Var rhs) =>
  _protocol_arithmetic(lhs, <mul>, <*>, rhs);

/** Multiplies matrices through a registered `matmul` behavior.
    `@` has no numeric meaning, so numeric operands raise `<bad-op>`; a
    protocol result keeps the ownership chosen by its callback.
*/
Var Var.matmul(Var lhs, Var rhs) =>
  _protocol_arithmetic(lhs, <matmul>, <@>, rhs);

/** Divides dynamic values through numeric or registered `div` behavior.
    Numeric integer zero divisors raise; floating division uses host infinity
    and NaN behavior. Other promotion, failure, and ownership follow
    `Var.binary`.
*/
meta native Var Var.div(Var lhs, Var rhs) =>
  _protocol_arithmetic(lhs, <div>, </>, rhs);

/** Computes dynamic remainder through integer or registered `mod` behavior.
    Numeric operands use the common promoted integer type and reject a zero
    divisor; floating operands are not accepted. Other failure and ownership
    follow `Var.binary`.
*/
meta native Var Var.mod(Var lhs, Var rhs) =>
  _protocol_arithmetic(lhs, <mod>, <%>, rhs);

static Var _protocol_arithmetic(Var lhs, Symbol member, Symbol op, Var rhs) {
  Var result = _fast_numeric(op, lhs, rhs);
  if (result.u64 != VAR_VOID_BITS) return result;
  _valid_operands(lhs, rhs);
  if (lhs is void || rhs is void) raise %(void-op (op $op));
  /* String is checked before descriptor dispatch. The `add` thunk from
     String's protocol row would get a NULL out of `Var.string` on a
     non-string operand instead of the raise below. */
  if (op == <+> && lhs is <string> && rhs is <string>)
    return lhs.string().add(rhs);
  if (lhs is <string>) return _general_numeric_binary(op, lhs, rhs);
  if (lhs.try_dispatch_binary(member, rhs, result)) return result;
  if (lhs.kind() == <object>) {
    Symbol tag = lhs.tag();
    raise %(no-member (tag $tag) (member $member));
  }
  return _general_numeric_binary(op, lhs, rhs);
}

/** Negates a dynamic value through registered `neg` or numeric subtraction.
    Without a selected protocol, this computes `0 - value` with ordinary `Var`
    promotion and wrapping, so a narrow integer promotes before negation.
    Raises: `<bad-enc>` for invalid bits, `<void-op>` for `void`, `<no-member>`
    for an object without `neg`, or any cause from protocol or numeric
    subtraction.
*/
meta native Var Var.neg(Var value) {
  _valid_operand(value);
  if (value is void) raise %(void-op (operation "Var.neg"));
  Var result;
  if (value.try_dispatch_unary(<neg>, result)) return result;
  if (value.kind() == <object>) {
    Symbol tag = value.tag();
    raise %(no-member (tag $tag) (member neg));
  }
  return Var.sub(0, value);
}

/* fast lanes

   The immediate i32/u32/f32 and unboxed f64 lanes shortcut the general
   decoder path. Recognition runs before encoding validation, so it stays
   conservative. For every operation it accepts, a lane must produce the
   general path's result tag, lane-width wrapping, signed division edge,
   shift rules, and cause. */

/* Returns `void` for an operator or operand pair no lane takes. */
static Var _fast_numeric(Symbol op, Var lhs, Var rhs) {
  if (!_numeric_operator(op)) return void;
  switch (_fast_numeric_tag(lhs, rhs)) {
    case <i32>: return _fast_i32(op, lhs.payload32(), rhs.payload32(), 0);
    case <u32>: return _fast_i32(op, lhs.payload32(), rhs.payload32(), 1);
    case <f32>: return _fast_f32(op, lhs, rhs);
    case <f64>: return _fast_f64(op, lhs, rhs);
  }
  return void;
}

static Var _fast_f32(Symbol op, Var lhs, Var rhs) {
  if (!_floating_operator(op)) return void;
  float a = lhs.decode_f32(), b = rhs.decode_f32();
  return Var.box_f32(_f32_step(op, a, b));
}

static Var _fast_f64(Symbol op, Var lhs, Var rhs) {
  if (!_floating_operator(op)) return void;
  double a = lhs.decode_f64(), b = rhs.decode_f64();
  return Var.box_f64(_f64_step(op, a, b));
}

/* The operators with a numeric meaning; `@` has none. */
static int _numeric_operator(Symbol op) {
  switch (op) {
    case <+>: case <->: case <*>: case </>: case <%>:
    case <&>: case <|>: case <^>: case <"<<">: case <">>">: return 1;
  }
  return 0;
}

/* The four operators floating arithmetic defines. */
static int _floating_operator(Symbol op) =>
  op == <+> || op == <-> || op == <*> || op == </>;

static inline Symbol _fast_numeric_tag(Var lhs, Var rhs) {
  unsigned long left_prefix = lhs.u64 & 0xFFFFFFFF00000000ul;
  unsigned long right_prefix = rhs.u64 & 0xFFFFFFFF00000000ul;
  if (left_prefix == right_prefix) {
    if (left_prefix == VAR_I32_PREFIX) return <i32>;
    if (left_prefix == VAR_U32_PREFIX) return <u32>;
    if (left_prefix == VAR_F32_PREFIX) return <f32>;
  }
  unsigned left_top = lhs.u64 >> 48, right_top = rhs.u64 >> 48;
  int left_f64 = (left_top >= 0x0010 && left_top <= 0x7FFF) ||
                 (left_top >= 0x8010 && lhs.u64 != VAR_VOID_BITS);
  int right_f64 = (right_top >= 0x0010 && right_top <= 0x7FFF) ||
                  (right_top >= 0x8010 && rhs.u64 != VAR_VOID_BITS);
  return left_f64 && right_f64 ? <f64> : 0;
}

static Var _fast_i32(Symbol op, unsigned a, unsigned b, int unsigned_value) {
  if ((op == <"<<"> || op == <">>">) && b >= 32)
    raise %(bad-shift (op $op) (count $b) (width 32));
  unsigned raw = _integer_raw(op, a, b, 32, unsigned_value);
  return unsigned_value ? Var.box_u32(raw) : Var.box_i32_bits(raw);
}

// general arithmetic

static Var _general_numeric_binary(Symbol op, Var lhs, Var rhs) {
  X2CVarNumeric left, right;
  lhs.numeric_decode(left);
  rhs.numeric_decode(right);
  switch (op) {
    case <"<<">: case <">>">:
      if (left.floating || right.floating) raise %(bad-types (op $op));
      return _shift_binary(op, left, right);
    case <%>: case <&>: case <|>: case <^>:
      if (left.floating || right.floating) raise %(bad-types (op $op));
      return _integer_binary(op, left, right);
    case <@>: raise %(bad-op (op $op));
    case <+>: case <->: case <*>: case </>: break;
  }
  if (left.floating || right.floating)
    return _floating_binary(op, left, right, _floating_tag(left, right));
  return _integer_binary(op, left, right);
}

static Var _integer_binary(Symbol op, X2CVarNumeric lhs, X2CVarNumeric rhs) {
  Symbol tag = _integer_result_tag(lhs, rhs);
  X2CVarNumericInfo info;
  Var.numeric_info(tag, info);
  unsigned long long raw = _integer_raw(
    op, _raw_for_width(lhs, info.bits), _raw_for_width(rhs, info.bits),
    info.bits, info.unsigned_value);
  return Var.integer_box(tag, raw);
}

/* C's usual arithmetic conversion, expressed in ranks. Narrow integers first
   promote to i32. Equal signedness chooses the wider rank; for a mixed pair,
   unsigned wins at equal-or-higher rank, otherwise signed wins only when its
   width covers the unsigned lane. Shifts do not use this common tag. A shift
   result keeps the promoted left tag. */
static Symbol _integer_result_tag(X2CVarNumeric &lhs, X2CVarNumeric &rhs) {
  _promote_integer(lhs);
  _promote_integer(rhs);
  if (lhs.unsigned_value == rhs.unsigned_value) {
    X2CVarNumeric *value = lhs.rank >= rhs.rank ? &lhs : &rhs;
    return Var.integer_tag(value.rank, value.unsigned_value);
  }
  X2CVarNumeric *unsigned_value = lhs.unsigned_value ? &lhs : &rhs;
  X2CVarNumeric *signed_value = lhs.unsigned_value ? &rhs : &lhs;
  if (unsigned_value.rank >= signed_value.rank)
    return Var.integer_tag(unsigned_value.rank, 1);
  if (signed_value.bits > unsigned_value.bits)
    return Var.integer_tag(signed_value.rank, 0);
  return Var.integer_tag(signed_value.rank, 1);
}

static void _promote_integer(X2CVarNumeric &value) {
  if (value.rank >= 3) return;
  if (!value.unsigned_value) value.raw = _extended(value);
  value.tag = <i32>;
  value.unsigned_value = 0;
  value.bits = 32;
  value.rank = 3;
}

static unsigned long long _raw_for_width(X2CVarNumeric &value, int bits) =>
  _extended(value) & Var.width_mask(bits);

/* A signed operand's bits sign-extend to 64; an unsigned operand's stay as
   they are. */
static unsigned long long _extended(X2CVarNumeric &value) =>
  value.unsigned_value ? value.raw
  : (unsigned long long) Var.signed_from_bits(value.raw, value.bits);

static Var _shift_binary(Symbol op, X2CVarNumeric lhs, X2CVarNumeric rhs) {
  _promote_integer(lhs);
  _promote_integer(rhs);
  unsigned long long count = _extended(rhs);
  if (!rhs.unsigned_value && (long long) count < 0)
    raise %(bad-shift (op $op));
  if (count >= (unsigned long long) lhs.bits)
    raise %(bad-shift (op $op) (count $count) (width $(lhs.bits)));
  unsigned long long raw = _integer_raw(
    op, _raw_for_width(lhs, lhs.bits), count, lhs.bits, lhs.unsigned_value);
  return Var.integer_box(lhs.tag, raw);
}

/* The wider floating operand's family; an integer operand never wins. */
static Symbol _floating_tag(X2CVarNumeric &lhs, X2CVarNumeric &rhs) {
  if (!rhs.floating) return lhs.tag;
  if (!lhs.floating) return rhs.tag;
  return lhs.rank >= rhs.rank ? lhs.tag : rhs.tag;
}

/* Both operands convert to the result family before the step. */
static Var _floating_binary(
  Symbol op, X2CVarNumeric lhs, X2CVarNumeric rhs, Symbol tag) {
  if (tag == <f32>) {
    float a = lhs.f32(), b = rhs.f32();
    return Var.box_f32(_f32_step(op, a, b));
  }
  if (tag == <f64>) {
    double a = lhs.f64(), b = rhs.f64();
    return Var.box_f64(_f64_step(op, a, b));
  }
  long double a = lhs.ldouble(), b = rhs.ldouble();
  return Var.box_long_double(_ldouble_step(op, a, b));
}

// comparisons

/** Evaluates `==` on two `Var` operands.
    Two numbers compare as their native values do in C after the usual
    arithmetic conversions, so `3 == 3L` and `-1 == 4294967295u` hold and a
    NaN equals nothing. Other values compare through `Var.equal`.
    Raises: `<bad-enc>` when a numeric comparison meets invalid `Var` bits.
*/
int x2c_var_equal(Var a, Var b) {
  if (a.u64 == b.u64) return !_nan(a);
  if (_numeric(a) && _numeric(b)) return _numeric_order(a, b) == 0;
  return a.equal(b);
}

/** Evaluates `===` on two `Var` operands.
    Two numbers are identical when they have the same tag and the same bits,
    so two boxes of one `long` are identical, `NaN === NaN` holds, and
    `+0.0 === -0.0` does not. Other values are identical when their `Var`
    bits are, as `Var.same` reports.
*/
int x2c_var_identical(Var a, Var b) => a.u64 == b.u64 || a.wide_equal(b);

/** Orders two `Var` operands for `<`, `<=`, `>`, and `>=`.
    Two numbers order as their native values do in C after the usual
    arithmetic conversions. The result is -1, 0, or 1, or NaN when a NaN
    leaves the pair unordered, so each relation to zero is false. Other
    values return the order `Var.compare` gives.
    Raises: `<void-op>` when either operand is `void`, and `<bad-enc>` when
    a numeric comparison meets invalid `Var` bits.
*/
double x2c_var_order(Var a, Var b) {
  if (_numeric(a) && _numeric(b)) return _numeric_order(a, b);
  return a.compare(b);
}

/* Most comparisons the compiler makes have a Symbol or a List operand, so
   this reads numberhood from the top 16 bits instead of the full decode in
   `Var.kind`. Below 0x0010 only the wide boxes are numbers, 0x8004 through
   0x800F hold Symbols and custom objects, and `void` is the one other
   non-number. */
static inline int _numeric(Var value) {
  unsigned top = value.u64 >> 48;
  if (top < 0x0010) return value.is_wide();
  if (top >= 0x8004 && top <= 0x800F) return 0;
  return value.u64 != VAR_VOID_BITS;
}

/* Equal bits hold equal values except NaN, which C makes unequal to itself.
   An `<f64>` NaN has the one `<nan>` encoding; an `<f32>` or `<ldouble>`
   NaN keeps its payload. */
static int _nan(Var value) {
  if (value.u64 == VAR_NAN_BITS) return 1;
  if ((value.u64 & 0xFFFFFFFF00000000ul) == VAR_F32_PREFIX) {
    float f = value.decode_f32();
    return f != f;
  }
  if (!value.is_wide()) return 0;
  long double x = value.long_double_value();
  return x != x;
}

/* C's usual arithmetic conversions bring a numeric pair to one type: the
   wider floating family when either operand is floating, otherwise the
   integer type arithmetic would produce. Returns -1, 0, or 1, or NaN for an
   unordered pair. */
static double _numeric_order(Var lhs, Var rhs) {
  X2CVarNumeric left, right;
  lhs.numeric_decode(left);
  rhs.numeric_decode(right);
  if (left.floating || right.floating) return _floating_order(left, right);
  X2CVarNumericInfo info;
  Var.numeric_info(_integer_result_tag(left, right), info);
  unsigned long long a = _raw_for_width(left, info.bits);
  unsigned long long b = _raw_for_width(right, info.bits);
  if (info.unsigned_value) return a < b ? -1 : a > b;
  long long x = Var.signed_from_bits(a, info.bits);
  long long y = Var.signed_from_bits(b, info.bits);
  return x < y ? -1 : x > y;
}

/* Widening the common floating family to `long double` keeps every value
   exact, so one comparison serves all three families. */
static double _floating_order(X2CVarNumeric &lhs, X2CVarNumeric &rhs) {
  long double a, b;
  switch (_floating_tag(lhs, rhs)) {
    case <f32>: a = lhs.f32(); b = rhs.f32(); break;
    case <f64>: a = lhs.f64(); b = rhs.f64(); break;
    default:    a = lhs.ldouble(); b = rhs.ldouble();
  }
  if (a < b) return -1;
  if (a > b) return 1;
  return a == b ? 0 : 0.0 / 0.0;
}

// truthiness

/** Returns dynamic truthiness through registered dispatch or built-in rules.
    Numeric and `Symbol` zero and null unhandled pointer-bearing values are
    false; their nonzero or nonnull counterparts are true. A registered truth
    callback supplies its own result, including for a custom object, so it may
    return false independently of object state. The call does not retain
    `value` or inspect the contents of an iterator itself.
    Raises: `<bad-enc>` for invalid `Var` bits, `<void-op>` for `void`, or
    `<bad-types>` when no truthiness rule exists, plus any cause raised by a
    selected descriptor callback.
*/
meta native int Var.truth(Var value) {
  if (!value.encoding_valid() || value is void) return value.fallback_truth();
  switch (value.tag()) {
    case <i8>: case <u8>: case <i16>: case <u16>: case <i32>: case <u32>:
      return value.payload32() != 0;
    case <i48>: case <u48>:
      return (value.u64 & ((1ul << 48) - 1)) != 0;
  }
  int handled = 0, truth = value.dispatch_truth(handled);
  return handled ? !!truth : value.fallback_truth();
}

/** Returns built-in truthiness without consulting a registered descriptor.
    Numeric and `Symbol` zero and null pointer-bearing values are false; other
    supported built-ins are true. Container-specific truth comes from dispatch.
    Raises: `<bad-enc>` for invalid `Var` bits, `<void-op>` for `void`, or
    `<bad-types>` when no truthiness rule exists.
*/
int Var.fallback_truth(Var value) {
  _valid_operand(value);
  if (value is void) raise %(void-op (operation "Var.truth"));
  X2CVarNumericInfo info;
  if (Var.numeric_info(value.tag(), info)) return _numeric_truth(value);
  Symbol kind = value.kind();
  if (kind == <symbol>) return value.symbol() != 0;
  if (kind == <pointer> || kind == <reference> || kind == <object>)
    return value.pointer() != NULL;
  Symbol source = value.tag();
  raise %(bad-types (source $source) (operation "truthy"));
}

static int _numeric_truth(Var value) {
  X2CVarNumeric numeric;
  value.numeric_decode(numeric);
  return numeric.floating ? numeric.floating_value != 0.0L : numeric.raw != 0;
}

// compound updates

/** Applies a failure-atomic dynamic compound update and returns the new value.
    The operation is limited to arithmetic, remainder, bitwise, and shift
    operators. The result is converted back to the destination's original tag
    and stored only after both computation and conversion complete; this does
    not provide thread synchronization. If a delegated protocol operation
    returns `void`, the function leaves the destination unchanged.
    Raises: `<bad-arg>` for a null destination, or any cause from
    `Var.binary` and `Var.convert`. These failures leave the stored value
    unchanged.
*/
Var Var.update(Var &?lhs, Symbol op, Var rhs) =>
  x2c_var_update_volatile(lhs, op, rhs);

/** Applies `Var.update` semantics to a volatile destination in generated code.
    Volatile preserves accesses across exception transfer, without providing
    thread synchronization.
*/
Var x2c_var_update_volatile(volatile Var &?lhs, Symbol op, Var rhs) {
  if (!lhs) raise %(bad-arg (operation "Var.update"));
  _valid_operands(lhs, rhs);
  if (lhs is void || rhs is void) raise %(void-op (op $op));
  if (!_numeric_operator(op)) raise %(bad-op (op $op));
  Var result = lhs.binary(op, rhs);
  if (result is void) return void;
  Var stored = _same_tag_update(lhs, rhs) ? result : result.convert(lhs.tag());
  lhs = stored;
  return stored;
}

/* Var.update skips conversion only when the fast binary path returns the
   operands' shared tag. Every other pair goes through Var.convert, which
   preserves the destination tag. */
static inline int _same_tag_update(Var lhs, Var rhs) {
  unsigned long left = lhs.u64 & 0xFFFFFFFF00000000ul;
  unsigned long right = rhs.u64 & 0xFFFFFFFF00000000ul;
  if (left == right)
    return left == VAR_I32_PREFIX || left == VAR_U32_PREFIX ||
           left == VAR_F32_PREFIX;
  if (left == VAR_I32_PREFIX || left == VAR_U32_PREFIX ||
      left == VAR_F32_PREFIX || right == VAR_I32_PREFIX ||
      right == VAR_U32_PREFIX || right == VAR_F32_PREFIX)
    return 0;
  if (lhs.is_wide() || rhs.is_wide()) return 0;
  return _fast_numeric_tag(lhs, rhs) == <f64>;
}

/** Applies dynamic postfix `++` or `--` and returns the prior value.
    The update adds or subtracts an `<i32>` one through `Var.update`,
    preserving the destination tag. If a delegated protocol operation returns
    `void`, the function leaves the destination unchanged and returns `void`.
    Raises: `<bad-arg>` for a null destination, `<bad-enc>` for invalid `Var`
    bits, `<void-op>` for `void`, `<bad-op>` for an operator other than
    `++` or `--`, or any cause from `Var.update`. These failures leave the
    stored value unchanged.
*/
Var Var.postfix(Var &?lhs, Symbol op) => x2c_var_postfix_volatile(lhs, op);

/** Applies `Var.postfix` semantics to a volatile destination in generated
    code. Volatile preserves accesses across exception transfer, without
    providing thread synchronization.
*/
Var x2c_var_postfix_volatile(volatile Var &?lhs, Symbol op) {
  if (!lhs) raise %(bad-arg (operation "Var.postfix"));
  _valid_operand(lhs);
  if (lhs is void) raise %(void-op (op $op));
  Symbol binary_op;
  if (op == <++>) binary_op = <+>;
  else if (op == <-->) binary_op = <->;
  else raise %(bad-op (op $op));
  Var old = lhs, one = Var.box_i32_bits(1);
  if (x2c_var_update_volatile(lhs, binary_op, one) is void) return void;
  return old;
}

static Var _native_update(Var lhs, Symbol target, Symbol op, Var rhs) {
  Var result = lhs.binary(op, rhs);
  if (result is void) return void;
  return result.convert(target);
}

/* operand checks

   The tests inline into the operators, and the raises live in helpers:
   clang does not inline a check that holds a raise's error construction.
   The side travels as a Symbol, because a String literal argument would
   add a lazy interning guard to the top of every operator. */

static inline void _valid_operand(Var value) {
  if (!value.encoding_valid()) _bad_bits(value);
}

/* The left operand is checked first. */
static inline void _valid_operands(Var lhs, Var rhs) {
  if (!lhs.encoding_valid()) _bad_side(lhs, <left>);
  if (!rhs.encoding_valid()) _bad_side(rhs, <right>);
}

static void _bad_bits(Var value) {
  unsigned long bits = value.u64;
  raise %(bad-enc (value $bits));
}

static void _bad_side(Var value, Symbol side) {
  unsigned long bits = value.u64;
  String text = side;
  raise %(bad-enc (value $bits) (side $text));
}
