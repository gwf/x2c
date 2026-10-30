/*  numbers.x -- numeric payloads and wide box lifetime */

static typedef union VarWideValue {
  long long_value;
  unsigned long ulong_value;
  long long long_long_value;
  unsigned long long ulong_long_value;
  long double long_double_value;
} VarWideValue;

/* Wide scalars are stored in Scope-owned boxes because their payload and tag
   cannot both fit in a Var. The encoding keeps the low 48 address bits and
   reuses the three alignment bits for the family; the tag stored in the box
   prevents one wide family from being decoded through another. Copying a Var
   aliases its box, while `Var.clone_wide` creates a distinct identity. */
static typedef struct VarWideBox {
  Symbol tag;
  VarWideValue value;
} *VarWideBox;

// wide scalars

/** Boxes a `long` into a scope-owned `<long>` value.
    A `Var` is eight bytes, and the tag consumes some of them. The five widest
    native families, `long`, `unsigned long`, `long long`, `unsigned long
    long`, and `long double`, cannot be stored inline. Boxing one allocates a
    small immutable box in the active scope, and the result lives for that
    scope's lifetime like any other scope allocation.

    Two boxes of the same number are equal and identical: `==` compares the
    values, and `===` compares the type and the value bits. `Var.same`
    compares the 64 `Var` bits, and therefore the box addresses.

    ```x2c
    ~Var five = Var.box_long(5L);
    ~Var also = Var.box_long(5L);
    printf("equal=%d identical=%d same=%d tag=%s\n", five == also,
           five === also, five.same(also), five.tag().str());
    ```
    Raises: `<alloc-fail>` when the box cannot be allocated and `<bad-enc>`
    when its address cannot be represented in a `Var`. Before `Error`
    initialization, allocation failure uses the raw fatal floor.
*/
Var Var.box_long(long value) {
  VarWideValue wide = {0};
  wide.long_value = value;
  return _new_wide(_long_, wide);
}

/** Boxes an `unsigned long` into a scope-owned `<ulong>` value.
    `<ulong>` is a distinct family from `<long>`. A box made here is never
    `Var.equal` or identical to one made by `Var.box_long`, even when both
    hold the same bit pattern, because `Var.wide_equal` requires matching
    tags. `==` converts the two as C does. Read it back with
    `Var.ulong_value`, the one reader that returns the payload unsigned.
    Raises: `<alloc-fail>` when the box cannot be allocated and `<bad-enc>`
    when its address cannot be represented in a `Var`. Before `Error`
    initialization, allocation failure uses the raw fatal floor.
*/
Var Var.box_ulong(unsigned long value) {
  VarWideValue wide = {0};
  wide.ulong_value = value;
  return _new_wide(_ulong_, wide);
}

/** Boxes a native signed long-long value without losing precision.
    Raises: `<alloc-fail>` when the box cannot be allocated and `<bad-enc>`
    when its address cannot be represented in a `Var`. Before `Error`
    initialization, allocation failure uses the raw fatal floor.
*/
Var Var.box_long_long(long long value) {
  VarWideValue wide = {0};
  wide.long_long_value = value;
  return _new_wide(_llong_, wide);
}

/** Boxes a native unsigned long-long value without losing precision.
    Raises: `<alloc-fail>` when the box cannot be allocated and `<bad-enc>`
    when its address cannot be represented in a `Var`. Before `Error`
    initialization, allocation failure uses the raw fatal floor.
*/
Var Var.box_ulong_long(unsigned long long value) {
  VarWideValue wide = {0};
  wide.ulong_long_value = value;
  return _new_wide(_ullong_, wide);
}

/** Boxes a `long double` into a scope-owned `<ldouble>` value.
    This is the only family that keeps a full `long double` payload. The tag
    names that C family; it does not promise a bit width. `Var.floating`
    narrows the value to `double`; `Var.long_double_value` preserves the
    extra precision.
    Raises: `<alloc-fail>` when the box cannot be allocated and `<bad-enc>`
    when its address cannot be represented in a `Var`. Before `Error`
    initialization, allocation failure uses the raw fatal floor.
*/
Var Var.box_long_double(long double value) {
  VarWideValue wide = {0};
  wide.long_double_value = value;
  return _new_wide(_ldouble_, wide);
}

/** Clones the wide numeric `value` into a new box in the active `Scope`.
    The clone is `==` and `===` to `value` but has its own box, so `Var.same`
    tells the two apart. Returns `void` when `value` is not wide.
    Raises: `<alloc-fail>` when the clone cannot be allocated, or `<bad-enc>`
    if its address cannot be represented in a `Var`.
*/
meta native Var Var.clone_wide(Var value) {
  if (!value.is_wide()) return void;
  VarWideBox source = _wide_box(value);
  VarWideBox box = xmalloc(sizeof(struct VarWideBox));
  *box = *source;
  uintptr_t raw = (uintptr_t) box;
  if ((raw & 0x7) != 0 || raw >= (1ul << 48)) {
    xfree(box);
    raise %(bad-enc (operation "Var.clone_wide"));
  }
  unsigned long pointer_mask = _bitmask(48) - 0x7;
  Var clone = value;
  clone.u64 = (clone.u64 & ~pointer_mask) | raw;
  return clone;
}

/** Moves a wide numeric box into the destination `Scope` held by `scope`.
    The box is not copied and `value` keeps its identity. If the destination
    slot is NULL, a new `Scope` is created there. Returns `value` unchanged for
    another family.
    For a wide value, raises `<bad-arg>` when `scope` is NULL, or
    `<alloc-fail>` when a new destination `Scope` cannot be allocated.
    Ownership is unchanged on failure.
*/
Self Var.move_wide_to(Self value, Scope *scope) {
  if (!value.is_wide()) return value;
  Scope.move(_wide_box(value), scope);
  return value;
}

/** Returns the `Scope` owning a live wide numeric box, or NULL otherwise. */
Scope Var.wide_owner(Var v) => v.is_wide() ? Scope.owner(_wide_box(v)) : NULL;

// payload readers

/** Returns `v`'s payload as a `double` when its tag is floating, or 0.0.
    Handles `<f32>`, `<f64>`, and `<ldouble>`, and reconstructs NaN,
    `+Inf`, and `-Inf` from their discrete tags. An `<ldouble>` payload is
    narrowed to `double`; call `Var.long_double_value` to keep the full
    precision.

    Like the other raw payload readers this one is silent. An integer, a
    `String`, or `void` reads as 0.0, and nothing distinguishes that from a
    stored zero. When the tag is not already known, convert with
    `Var.convert` in `lib/var/conversion.x`, which raises a conversion failure;
    the scalar-named readers such as `Var.double` do this for you.

    An unhandled tag yields 0.0.
*/
meta native double Var.floating(Var v) {
  switch (v.tag()) {
    case <f32>:     return v.decode_f32();
    case <f64>:     return _f64_floating(v);
    case <"nan">:   return  0.0 / 0.0;
    case <"-inf">:  return -1.0 / 0.0;
    case <"+inf">:  return  1.0 / 0.0;
    case <ldouble>: return (double) _wide_box(v).value.long_double_value;
  }
  return 0.0;
}

/** Returns `v`'s payload as a `long` when its tag is integral, or 0.
    This reads the payload; it does not convert. It decodes every integer
    family, from `<u8>` through `<ullong>`, including the scope-owned boxes,
    and returns 0 for a tag it does not handle. A `double` reads as 0, and so
    does a `String`; nothing reports the mismatch. A `<ullong>` or `<llong>`
    payload is truncated to `long`, and a `<ulong>` above `LONG_MAX` comes back
    negative. `Var.ulong_value` preserves the unsigned payload. A
    `Symbol` reads as its numeric `Symbol` value.

    When the tag might not be what you expect, convert instead of reading.
    `Var.convert` in `lib/var/conversion.x` raises a conversion failure.
    Assigning a `Var` to an `int` or a `long`, and the scalar-named readers
    such as `Var.int`, go through `Var.convert` too.

    ```x2c
    ~Var text = "ada";
    ~Var small = (unsigned char) 44;
    printf("small=%ld text=%ld\n", small.integer(), text.integer());
    ```

    An unhandled tag yields 0.
*/
meta native long Var.integer(Var v) {
  unsigned top = _top_bits(v);
  if (top == x2c_var_taginfo[_u48_].top) return v.u64 & _bitmask(48);
  if (top == x2c_var_taginfo[_i48_].top) return _i48_integer(v);
  /* The 8-, 16-, and 32-bit rows share one top and differ in the middle.
     The switch stays here: in a helper that returns 0 for another middle,
     clang computes all six arms and selects one, 11 more instructions. */
  if (top == x2c_var_taginfo[_u8_].top) {
    switch (_middle_bits(v)) {
      case 0x1: return (unsigned char)  (v.u64 & _bitmask(8));
      case 0x2: return (char)           (v.u64 & _bitmask(8));
      case 0x3: return (unsigned short) (v.u64 & _bitmask(16));
      case 0x4: return (short)          (v.u64 & _bitmask(16));
      case 0x5: return (unsigned int)   (v.u64 & _bitmask(32));
      case 0x6: return (int)            (v.u64 & _bitmask(32));
    }
  }
  if (top == 0x0005) return _wide_integer(v);
  if (top == 0x0007 && _bottom_bits(v) == 0x6)
    return (long) _wide_box(v).value.ulong_long_value;
  /* The offset comes from the table: with the VAR_SYMBOL_OFFSET constant,
     clang also subtracts it on the path of every other tag. */
  if (top >= 0x8004 && top <= 0x800B) {
    unsigned long const offset = x2c_var_taginfo[_symbol_].top << 48;
    return (Symbol) (v.u64 - offset);
  }
  return 0;
}

/** Returns the payload of a `<long>` box, or 0 if `v` has a different tag.
    The test is on the tag, so a `<ulong>`, `<llong>`, or `<i32>` value
    reads as 0 with no complaint. `Var.integer` accepts any integer family;
    use this one when the tag is known and the payload must survive intact.

    A tag mismatch yields 0.
*/
meta native long Var.long_value(Var v) =>
  v is <long> ? _wide_box(v).value.long_value : 0;

/** Returns the payload of a `<ulong>` box, or 0 if `v` has a different tag.
    Prefer this to `Var.integer` for a `<ulong>`: the general reader casts the
    payload to `long`, which reinterprets anything above `LONG_MAX` as
    negative, while this reader returns the unsigned value. A tag that is
    not `<ulong>` yields 0 silently, so test with `Var.is` when the tag is in
    doubt.

    A tag mismatch yields 0.
*/
meta native unsigned long Var.ulong_value(Var v) =>
  v is <ulong> ? _wide_box(v).value.ulong_value : 0;

/** Returns an `<llong>` box's signed payload, or 0 for another tag. */
meta native long long Var.long_long_value(Var v) =>
  v is <llong> ? _wide_box(v).value.long_long_value : 0;

/** Returns a `<ullong>` box's unsigned payload, or 0 for another tag. */
meta native unsigned long long Var.ulong_long_value(Var v) =>
  v is <ullong> ? _wide_box(v).value.ulong_long_value : 0;

/* wide equality

   A wide box holds one or two machine words, so it mixes as words rather
   than as bytes. The tag seeds the chain, so two boxes with equal bits but
   different tags hash differently. */

/** Returns a supported wide scalar box's content hash, or 0 otherwise. */
unsigned Var.wide_hash(Var v) {
  if (!v.is_wide()) return 0;
  VarWideValue *value = &_wide_box(v).value;
  Symbol tag = v.tag();
  switch (tag) {
    case <long>:    return _hash_wide(tag, value, sizeof(long));
    case <ulong>:   return _hash_wide(tag, value, sizeof(unsigned long));
    case <llong>:   return _hash_wide(tag, value, sizeof(long long));
    case <ullong>:  return _hash_wide(tag, value, sizeof(unsigned long long));
    case <ldouble>: return _hash_wide(tag, value, sizeof(long double));
  }
  return 0;
}

/** Reports content equality for supported wide scalar boxes.
    Boxed `<long>`, `<ulong>`, `<llong>`, `<ullong>`, and `<ldouble>` values
    are separate allocations, so bit identity says nothing about their
    contents. This is the payload comparison that `Var.equal` and `===` use
    for those tags. An `<ldouble>` pair is compared byte for byte, so two NaNs
    sharing one representation compare equal here.

    A 0 result means "not equal as wide boxes". It also covers an argument
    that is not a wide box and a pair whose tags differ. For a general
    equality test use `Var.equal`, which covers every family, or `==`, which
    compares two numbers as C does.
*/
int Var.wide_equal(Var a, Var b) {
  if (!a.is_wide() || !b.is_wide()) return 0;
  Symbol tag = a.tag();
  if (tag != b.tag()) return 0;
  VarWideBox abox = _wide_box(a), bbox = _wide_box(b);
  switch (tag) {
    case <long>:  return abox.value.long_value == bbox.value.long_value;
    case <ulong>:  return abox.value.ulong_value == bbox.value.ulong_value;
    case <llong>:
      return abox.value.long_long_value == bbox.value.long_long_value;
    case <ullong>:
      return abox.value.ulong_long_value == bbox.value.ulong_long_value;
    case <ldouble>: return !memcmp(
      &abox.value.long_double_value, &bbox.value.long_double_value,
      sizeof(abox.value.long_double_value));
  }
  return 0;
}

/** Orders two wide boxes carrying the same tag, returning -1, 0, or 1.
    Integer families delegate to `Var.integer_compare`. An `<ldouble>` pair
    compares as `long double` and falls back to a byte comparison when neither
    operand is less than the other, so distinct NaN representations still
    order deterministically.

    0 means equal, and it is also the result for mismatched tags and for an
    argument that is not a wide box. Check the tags first, or use
    `Var.compare`, the runtime's full ordering.
*/
int Var.wide_compare(Var a, Var b) {
  if (!a.is_wide() || !b.is_wide()) return 0;
  Symbol tag = a.tag();
  if (tag != b.tag()) return 0;
  if (tag != <ldouble>) return a.integer_compare(b);
  long double av = a.long_double_value(), bv = b.long_double_value();
  if (av < bv) return -1;
  if (av > bv) return 1;
  int cmp = memcmp(
    &_wide_box(a).value.long_double_value,
    &_wide_box(b).value.long_double_value, sizeof(av));
  return cmp < 0 ? -1 : cmp > 0 ? 1 : 0;
}

/** Returns the payload of an `<ldouble>` box, or 0.0 if `v` has another tag.
    This is the only reader that preserves a `long double`. Every other
    floating tag, `<f64>` included, yields 0.0 here instead of being widened.
    `Var.floating` is the general floating reader.

    A tag mismatch yields 0.0.
*/
meta native long double Var.long_double_value(Var v) =>
  v is <ldouble> ? _wide_box(v).value.long_double_value : 0.0L;

static Var _new_wide(TagId id, VarWideValue value) {
  VarWideBox box = xmalloc(sizeof(struct VarWideBox));
  box.tag = x2c_var_taginfo[id].tag;
  box.value = value;
  uintptr_t raw = (uintptr_t) box;
  if ((raw & 0x7) != 0 || raw >= (1ul << 48)) {
    xfree(box);
    raise %(bad-enc (operation "Var.box"));
  }
  Var v = { .u64 = raw };
  v.u64 |= x2c_var_taginfo[id].top << 48;
  v.u64 |= x2c_var_taginfo[id].bottom;
  return v;
}

static VarWideBox _wide_box(Var v) => (VarWideBox) _address(v);

/* `Var.decode_f64` would first test the NaN and infinity patterns, which an
   `<f64>` tag has already excluded. */
static double _f64_floating(Var v) {
  unsigned long u = v.u64 == VAR_F64_NEG_MAX_ESCAPE
                  ? VAR_F64_NEG_MAX_RAW : v.u64 - VAR_F64_SHIFT;
  double d;
  memcpy(&d, &u, sizeof d);
  return d;
}

static long _i48_integer(Var v) {
  unsigned long mask = _bitmask(48), raw = v.u64 & mask;
  if (raw & (1ul << 47)) return -(long) ((~raw & mask) + 1ul);
  return (long) raw;
}

/* `<long>`, `<ulong>`, and `<llong>` share top 0x0005. */
static long _wide_integer(Var v) {
  switch (_bottom_bits(v)) {
    case 0x5: return _wide_box(v).value.long_value;
    case 0x6: return (long) _wide_box(v).value.ulong_value;
    case 0x7: return (long) _wide_box(v).value.long_long_value;
  }
  return 0;
}

/* Every member of the box's union starts at the union, so a family's
   payload is its first `width` bytes. Each arm passes a constant width,
   which lets `x2c_hash_bytes` unroll its word loop. */
static unsigned _hash_wide(Symbol tag, VarWideValue *value, size_t width) =>
  x2c_hash_bytes((unsigned) tag, value, width);

module int _wide_encoding_valid(Var value, Symbol tag) {
  VarWideBox box = _wide_box(value);
  return box && box.tag == tag;
}
