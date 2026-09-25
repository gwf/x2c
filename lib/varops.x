/*  varops.x -- boxed `Var` operators, updates, and truthiness

    `Var` arithmetic applies C-style numeric promotion to runtime tags, wraps
    integer results to the selected type's width, and delegates eligible object
    operations through registered protocols. Compound updates compute and
    convert completely before changing their destination.
 */

#pragma once

$(import "error-macros.xmacro")
$(import "integer-ops.xmacro")
#include "common.x"
#include "meta.x"
#include "varconvert.x"

// After the includes: a `.xmacro` borrows this unit's symbol table, and the
// `meta` functions in it call the compiler surface `meta.x` declares.
$(import "varops.xmacro")

// declared here because shallow symbol collection does not expand macros
char x2c_var_update_i8(volatile char *lhs, Symbol op, Var rhs);
signed char x2c_var_update_schar(
  volatile signed char *lhs, Symbol op, Var rhs);
uchar x2c_var_update_u8(volatile uchar *lhs, Symbol op, Var rhs);
short x2c_var_update_i16(volatile short *lhs, Symbol op, Var rhs);
ushort x2c_var_update_u16(volatile ushort *lhs, Symbol op, Var rhs);
int x2c_var_update_i32(volatile int *lhs, Symbol op, Var rhs);
uint x2c_var_update_u32(volatile uint *lhs, Symbol op, Var rhs);
long x2c_var_update_long(volatile long *lhs, Symbol op, Var rhs);
ulong x2c_var_update_ulong(volatile ulong *lhs, Symbol op, Var rhs);
long long x2c_var_update_long_long(
  volatile long long *lhs, Symbol op, Var rhs);
unsigned long long x2c_var_update_ulong_long(
  volatile unsigned long long *lhs, Symbol op, Var rhs);
float x2c_var_update_f32(volatile float *lhs, Symbol op, Var rhs);
double x2c_var_update_f64(volatile double *lhs, Symbol op, Var rhs);
long double x2c_var_update_long_double(
  volatile long double *lhs, Symbol op, Var rhs);

/* Each row supplies the storage boxer and decoder for its type, and
   `_native_update` performs the operation and the conversion back. Keeping
   both here makes compiler-lowered native lvalues and direct Var compound
   updates behave the same way. */
macro Unit $native.update(Type $type, Name $function, Literal $row) {
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
    volatile $type *$(x2c.ident "lhs"), Symbol $(x2c.ident "op"),
    Var $(x2c.ident "rhs")) {
    if (!$(x2c.ident "lhs")) {
      raise %(bad-arg (owner ${
        $(x2c.literal.string (x2c.binding.spelling $function))
      }));
    }
    Var $converted = _native_update(
      $(_update_box $row (x2c.ident "lhs")),
      $(_update_tag $row), $(x2c.ident "op"), $(x2c.ident "rhs"));
    if ($converted is void) return $(_update_zero $row);
    $type value = $(_update_decode $row (x2c.expr.ident $converted));
    ($(x2c.ident "lhs"))[0] = value;
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

#pragma private

#include "var.x"
#include "dispatch.x"
#include "string.x"
#include "array.x"
#include "map.x"

$integer.raw(_integer_raw);

/* The immediate i32/u32/f32 and unboxed f64 paths shortcut the general
   decoder path. Recognition runs before encoding validation, so it stays
   conservative. For every operation it accepts, the fast path must produce
   the general path's result tag, lane-width wrapping, signed division edge,
   shift rules, and cause. An unsupported pair clears `handled` and returns
   `void` as a marker. */
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

static unsigned long long _raw_for_width(X2CVarNumeric &value, int bits) {
  unsigned long long raw = value.unsigned_value ? value.raw
                         : (unsigned long long)
                           Var.signed_from_bits(value.raw, value.bits);
  return raw & Var.width_mask(bits);
}

static void _promote_integer(X2CVarNumeric &value) {
  if (value.rank >= 3) return;
  if (!value.unsigned_value)
    value.raw = (unsigned long long)
                 Var.signed_from_bits(value.raw, value.bits);
  value.tag = <i32>;
  value.unsigned_value = 0;
  value.bits = 32;
  value.rank = 3;
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

static Var _integer_binary(Symbol op, X2CVarNumeric lhs, X2CVarNumeric rhs) {
  Symbol tag = _integer_result_tag(lhs, rhs);
  X2CVarNumericInfo info;
  if (!Var.numeric_info(tag, &info)) raise %(bad-types (op $op));
  unsigned long long raw = _integer_raw(
    op, _raw_for_width(lhs, info.bits), _raw_for_width(rhs, info.bits),
    info.bits, info.unsigned_value);
  return Var.integer_box(tag, raw);
}

static Var _shift_binary(Symbol op, X2CVarNumeric lhs, X2CVarNumeric rhs) {
  _promote_integer(lhs);
  _promote_integer(rhs);
  if (!rhs.unsigned_value && Var.signed_from_bits(rhs.raw, rhs.bits) < 0)
    raise %(bad-shift (op $op));
  unsigned long long count = rhs.unsigned_value ? rhs.raw
                           : (unsigned long long)
                             Var.signed_from_bits(rhs.raw, rhs.bits);
  if (count >= (unsigned long long) lhs.bits)
    raise %(bad-shift (op $op) (count $count) (width ${lhs.bits}));
  unsigned long long raw = _integer_raw(
    op, _raw_for_width(lhs, lhs.bits), count, lhs.bits, lhs.unsigned_value);
  return Var.integer_box(lhs.tag, raw);
}

static Var _floating_binary(
  Symbol op, Var lhs_value, X2CVarNumeric &lhs, Var rhs_value,
  X2CVarNumeric &rhs) {
  Symbol tag = lhs.floating && lhs.rank >= rhs.rank ? lhs.tag : rhs.tag;
  if (!lhs.floating) tag = rhs.tag;
  if (!rhs.floating) tag = lhs.tag;
  Var left = lhs_value.convert(tag);
  Var right = rhs_value.convert(tag);
  Var result;
  if (tag == <f32>) {
    float a = left.float(), b = right.float(), value;
    switch (op) {
      case <+>: value = a + b; break;
      case <->: value = a - b; break;
      case <*>: value = a * b; break;
      case </>: value = a / b; break;
      default: raise %(bad-op (op $op));
    }
    result = Var.box_f32(value);
  }
  else if (tag == <f64>) {
    double a = left.floating(), b = right.floating(), value;
    switch (op) {
      case <+>: value = a + b; break;
      case <->: value = a - b; break;
      case <*>: value = a * b; break;
      case </>: value = a / b; break;
      default: raise %(bad-op (op $op));
    }
    result = Var.box_f64(value);
  }
  else {
    long double a = left.long_double_value();
    long double b = right.long_double_value(), value;
    switch (op) {
      case <+>: value = a + b; break;
      case <->: value = a - b; break;
      case <*>: value = a * b; break;
      case </>: value = a / b; break;
      default: raise %(bad-op (op $op));
    }
    result = Var.box_long_double(value);
  }
  return result;
}

static Var _general_numeric_binary(Symbol op, Var lhs_value, Var rhs_value) {
  X2CVarNumeric lhs, rhs;
  lhs_value.numeric_decode(&lhs);
  rhs_value.numeric_decode(&rhs);
  switch (op) {
    case <"<<">: case <">>">:
      if (lhs.floating || rhs.floating) raise %(bad-types (op $op));
      return _shift_binary(op, lhs, rhs);
    case <%>: case <&>: case <|>: case <^>:
      if (lhs.floating || rhs.floating) raise %(bad-types (op $op));
      return _integer_binary(op, lhs, rhs);
    case <@>: raise %(bad-op (op $op));
    case <+>: case <->: case <*>: case </>: break;
  }
  if (lhs.floating || rhs.floating)
    return _floating_binary(op, lhs_value, lhs, rhs_value, rhs);
  return _integer_binary(op, lhs, rhs);
}

static Var _fast_i32(Symbol op, unsigned a, unsigned b, int unsigned_value) {
  if ((op == <"<<"> || op == <">>">) && b >= 32)
    raise %(bad-shift (op $op) (count $b) (width 32));
  unsigned raw = _integer_raw(op, a, b, 32, unsigned_value);
  return unsigned_value ? Var.box_u32(raw) : Var.box_i32_bits(raw);
}

static Var _fast_numeric(Symbol op, Var lhs, Var rhs, int &handled) {
  switch (op) {
    case <+>: case <->: case <*>: case </>: case <%>:
    case <&>: case <|>: case <^>: case <"<<">: case <">>">: break;
    default: handled = 0;
      return void;
  }
  Symbol tag = _fast_numeric_tag(lhs, rhs);
  handled = 1;
  switch (tag) {
    case <i32>:
      return _fast_i32(op, lhs.payload32(), rhs.payload32(), 0);
    case <u32>:
      return _fast_i32(op, lhs.payload32(), rhs.payload32(), 1);
    case <f32>: {
      if (op != <+> && op != <-> && op != <*> && op != </>) break;
      float a = lhs.decode_f32(), b = rhs.decode_f32();
      float value = op == <+> ? a + b : op == <-> ? a - b
                  : op == <*> ? a * b : a / b;
      return Var.box_f32(value);
    }
    case <f64>: {
      if (op != <+> && op != <-> && op != <*> && op != </>) break;
      double a = lhs.decode_f64(), b = rhs.decode_f64();
      double value = op == <+> ? a + b : op == <-> ? a - b
                   : op == <*> ? a * b : a / b;
      return Var.box_f64(value);
    }
  }
  handled = 0;
  return void;
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

static int _update_operator(Symbol op) {
  switch (op) {
    case <+>: case <->: case <*>: case </>: case <%>: case <@>:
    case <&>: case <|>: case <^>: case <"<<">: case <">>">: return 1;
  }
  return 0;
}

/** Returns built-in truthiness without consulting a registered descriptor.
    Numeric and `Symbol` zero and null pointer-bearing values are false; other
    supported built-ins are true. Container-specific truth comes from dispatch.
    Raises: `<bad-enc>` for invalid `Var` bits, `<void-op>` for `void`, or
    `<bad-types>` when no truthiness rule exists.
*/
int Var.fallback_truth(Var value) {
  if (!value.encoding_valid()) {
    unsigned long bits = value.u64;
    raise %(bad-enc (value $bits));
  }
  if (value is void) raise %(void-op (owner "Var.truth"));
  X2CVarNumericInfo info;
  int truth;
  if (Var.numeric_info(value.tag(), &info)) {
    X2CVarNumeric numeric;
    value.numeric_decode(&numeric);
    truth = numeric.floating ? numeric.floating_value != 0.0L
          : numeric.raw != 0;
  }
  else {
    Symbol kind = value.kind();
    if (kind == <symbol>) truth = value.symbol() != 0;
    else if (kind == <pointer> || kind == <reference> || kind == <object>)
      truth = value.pointer() != NULL;
    else {
      Symbol source = value.tag();
      raise %(bad-types (source $source) (operation "truthy"));
    }
  }
  return !!truth;
}

meta int Var.truth(Var value);

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
int Var.truth(Var value) {
  if (!value.encoding_valid() || value is void)
    return value.fallback_truth();
  int handled = 0, truth = value.dispatch_truth(&handled);
  return handled ? !!truth : value.fallback_truth();
}

static Var _protocol_arithmetic(Var lhs, Symbol member, Symbol op, Var rhs) {
  int fast_handled;
  Var result = _fast_numeric(op, lhs, rhs, fast_handled);
  if (fast_handled) return result;
  if (!lhs.encoding_valid()) {
    unsigned long bits = lhs.u64;
    raise %(bad-enc (value $bits) (side "left"));
  }
  if (!rhs.encoding_valid()) {
    unsigned long bits = rhs.u64;
    raise %(bad-enc (value $bits) (side "right"));
  }
  if (lhs is void || rhs is void) raise %(void-op (op $op));
  /* String is checked before descriptor dispatch. The `add` thunk from
     String's protocol row would get a NULL out of `Var.string` on a
     non-string operand instead of the raise below. */
  if (op == <+> && lhs is <string> && rhs is <string>)
    return lhs.string().add(rhs);
  if (lhs is <string>) return _general_numeric_binary(op, lhs, rhs);
  if (lhs.try_dispatch_binary(member, rhs, &result)) return result;
  if (lhs.kind() == <object>) {
    Symbol tag = lhs.tag();
    raise %(no-member (tag $tag) (member $member));
  }
  return _general_numeric_binary(op, lhs, rhs);
}

meta Var Var.add(Var lhs, Var rhs);

/** Adds dynamic values through numeric, `String`, or registered `add`
    behavior.
    Numeric promotion, failure, and result ownership follow `Var.binary`;
    `String` addition returns a canonical concatenation, and a protocol result
    keeps the ownership chosen by its callback.
*/
Var Var.add(Var lhs, Var rhs) => _protocol_arithmetic(lhs, <add>, <+>, rhs);

meta Var Var.sub(Var lhs, Var rhs);

/** Subtracts dynamic values through numeric or registered `sub` behavior.
    Numeric promotion, failure, and result ownership follow `Var.binary`; a
    protocol result keeps the ownership chosen by its callback.
*/
Var Var.sub(Var lhs, Var rhs) => _protocol_arithmetic(lhs, <sub>, <->, rhs);

meta Var Var.mul(Var lhs, Var rhs);

/** Multiplies dynamic values through numeric or registered `mul` behavior.
    Numeric promotion, failure, and result ownership follow `Var.binary`; a
    protocol result keeps the ownership chosen by its callback.
*/
Var Var.mul(Var lhs, Var rhs) => _protocol_arithmetic(lhs, <mul>, <*>, rhs);

/** Multiplies matrices through a registered `matmul` behavior.
    `@` has no numeric meaning, so numeric operands raise `<bad-op>`; a
    protocol result keeps the ownership chosen by its callback.
*/
Var Var.matmul(Var lhs, Var rhs) =>
  _protocol_arithmetic(lhs, <matmul>, <@>, rhs);

meta Var Var.div(Var lhs, Var rhs);

/** Divides dynamic values through numeric or registered `div` behavior.
    Numeric integer zero divisors raise; floating division uses host infinity
    and NaN behavior. Other promotion, failure, and ownership follow
    `Var.binary`.
*/
Var Var.div(Var lhs, Var rhs) => _protocol_arithmetic(lhs, <div>, </>, rhs);

meta Var Var.mod(Var lhs, Var rhs);

/** Computes dynamic remainder through integer or registered `mod` behavior.
    Numeric operands use the common promoted integer type and reject a zero
    divisor; floating operands are not accepted. Other failure and ownership
    follow `Var.binary`.
*/
Var Var.mod(Var lhs, Var rhs) => _protocol_arithmetic(lhs, <mod>, <%>, rhs);

meta Var Var.neg(Var value);

/** Negates a dynamic value through registered `neg` or numeric subtraction.
    Without a selected protocol, this computes `0 - value` with ordinary `Var`
    promotion and wrapping, so a narrow integer promotes before negation.
    Raises: `<bad-enc>` for invalid bits, `<void-op>` for `void`, `<no-member>`
    for an object without `neg`, or any cause from protocol or numeric
    subtraction.
*/
Var Var.neg(Var value) {
  if (!value.encoding_valid()) {
    unsigned long bits = value.u64;
    raise %(bad-enc (value $bits));
  }
  if (value is void) raise %(void-op (owner "Var.neg"));
  Var result;
  if (value.try_dispatch_unary(<neg>, &result)) return result;
  if (value.kind() == <object>) {
    Symbol tag = value.tag();
    raise %(no-member (tag $tag) (member neg));
  }
  return Var.sub(0, value);
}

/** Applies a dynamic arithmetic, bitwise, comparison, or logical operator.
    Integers use C-style promotion and wrap to the result type's width;
    shifts use the promoted left operand's type and sign-fill signed right
    shifts. Floating arithmetic uses the widest floating-point operand type.
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
    case <@>: return lhs.matmul(rhs);
  }
  int fast_handled;
  Var result = _fast_numeric(op, lhs, rhs, fast_handled);
  if (fast_handled) return result;
  if (!lhs.encoding_valid()) {
    unsigned long bits = lhs.u64;
    raise %(bad-enc (value $bits) (side "left"));
  }
  if (!rhs.encoding_valid()) {
    unsigned long bits = rhs.u64;
    raise %(bad-enc (value $bits) (side "right"));
  }
  switch (op) {
    case <==>:  return Var.box_i32_bits((unsigned) (lhs == rhs));
    case <!=>:  return Var.box_i32_bits((unsigned) (lhs != rhs));
    case <===>: return Var.box_i32_bits((unsigned) (lhs === rhs));
    case <!==>: return Var.box_i32_bits((unsigned) (lhs !== rhs));
  }
  if (lhs is void || rhs is void) raise %(void-op (op $op));
  int predicate;
  switch (op) {
    case <"<">:  predicate = lhs < rhs; break;
    case <"<=">: predicate = lhs <= rhs; break;
    case <">">:  predicate = lhs > rhs; break;
    case <">=">: predicate = lhs >= rhs; break;
    case <&&>: case <||>: {
      int left_truth = lhs.truth(), right_truth = rhs.truth();
      predicate = op == <&&> ? left_truth && right_truth
                             : left_truth || right_truth;
      break;
    }
    case <&>: case <|>: case <^>: case <"<<">: case <">>">:
      return _general_numeric_binary(op, lhs, rhs);
    default: raise %(bad-op (op $op));
  }
  return Var.box_i32_bits((unsigned) !!predicate);
}

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
Var Var.update(Var *lhs, Symbol op, Var rhs) {
  if (!lhs) raise %(bad-arg (owner "Var.update"));
  if (!lhs[0].encoding_valid()) {
    unsigned long bits = lhs[0].u64;
    raise %(bad-enc (value $bits) (side "left"));
  }
  if (!rhs.encoding_valid()) {
    unsigned long bits = rhs.u64;
    raise %(bad-enc (value $bits) (side "right"));
  }
  if (lhs[0] is void || rhs is void) raise %(void-op (op $op));
  if (!_update_operator(op)) raise %(bad-op (op $op));
  Var result = lhs[0].binary(op, rhs);
  if (result is void) return void;
  if (_same_tag_update(lhs[0], rhs)) {
    lhs[0] = result;
    return result;
  }
  Var converted = result.convert(lhs[0].tag());
  lhs[0] = converted;
  return converted;
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
Var Var.postfix(Var *lhs, Symbol op) {
  if (!lhs) raise %(bad-arg (owner "Var.postfix"));
  if (!lhs[0].encoding_valid()) {
    unsigned long bits = lhs[0].u64;
    raise %(bad-enc (value $bits));
  }
  if (lhs[0] is void) raise %(void-op (op $op));
  Symbol binary_op;
  if (op == <++>) binary_op = <+>;
  else if (op == <-->) binary_op = <->;
  else
    raise %(bad-op (op $op));
  Var old = lhs[0], one = Var.box_i32_bits(1);
  if (lhs.update(binary_op, one) is void) return void;
  return old;
}

static Var _native_update(Var lhs, Symbol target, Symbol op, Var rhs) {
  Var result = lhs.binary(op, rhs);
  if (result is void) return void;
  return result.convert(target);
}
