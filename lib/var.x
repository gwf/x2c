/*  var.x -- variant type for dynamic typing

    Copyright (c) 2025 Gary William Flake

    `Var` encodes dynamic values in one 64-bit word. Its layout uses the IEEE
    754 double-precision ranges:

    0000:0000:0000:0000 - 7FEF:FFFF:FFFF:FFFF : [+0.0, MAX_DOUBLE]
    7FF0:0000:0000:0000 - 7FFF:FFFF:FFFF:FFFF : [+Inf, +NaNs]
    8000:0000:0000:0000 - FFEF:FFFF:FFFF:FFFF : [-0.0, MIN_DOUBLE]
    FFF0:0000:0000:0000 - FFFF:FFFF:FFFF:FFFF : [-Inf, -NaNs]

    Special-value ranges carry custom tags and payloads. An f64 is shifted by
    (1 << 52); shifted -DBL_MAX has a reserved encoding because all-one bits
    mean `void`. Native pointers retain their raw lower 48 address bits.

    The 64-bit `Var` layout is structured as follows:

    Tag : Payload         Tag : Payload        bits  Use
    -------------------   -------------------  ----  -------------------------
    0000:0000:0000:0000 - 0000:FFFF:FFFF:FFFF  48+0  `void`*
    0001:0000:0000:0000 - 0001:FFFF:FFFF:FFFF  48+0  u8*
    0002:0000:0000:0000 - 0002:FFFF:FFFF:FFFF  48+0  i8*
    0003:0000:0000:0000 - 0003:FFFF:FFFF:FFFF  47+1  u16*,i16*
    0004:0000:0000:0000 - 0004:FFFF:FFFF:FFFF  46+2  u32*,i32*,f32*,ulong*
    0005:0000:0000:0000 - 0005:FFFF:FFFF:FFFF  45+3  long*,f64*,ldouble*,
                                                      llong*,ullong*,long,
                                                      ulong,llong
    0006:0000:0000:0000 - 0007:FFFF:FFFF:FFFF  45+3  builtin pointer families,
                                                      ullong,ldouble
    0008:0000:0000:0000 - 000B:FFFF:FFFF:FFFF  45+3  builtin (Class) x 32
    000C:0000:0000:0000 - 000F:FFFF:FFFF:FFFF  45+3  builtin (Class *) x 32
    0010:0000:0000:0000 - 7FFF:FFFF:FFFF:FFFF  64+0  f64 > 0 + (52<<1)
    8000:0000:0000:0000 - 8000:FFFF:FFFF:FFFF  48+0  u48
    8001:0000:0000:0000 - 8001:FFFF:FFFF:FFFF  48+0  i48
    8002:0000:0000:0000 - 8002:FFFF:FFFF:FFFF  32+16 32-bit vals, 16-bit tag
    8003:0000:0000:0000 - 8003:FFFF:FFFF:FFFF  32+16 Special values
    8004:0000:0000:0000 - 800B:FFFF:FFFF:FFFF  50+1  `Symbol`s
    800C:0000:0000:0000 - 800F:FFFF:FFFF:FFFF  45+3  user (Class)* 32
    8010:0000:0000:0000 - FFFF:FFFF:FFFF:FFFF  64+0  f64 < 0 + (52<<1)
    -------------------   -------------------  ----  -------------------------

    A `Var` preserves its runtime kind. `void` is excluded from value-bearing
    protocols.
*/

#pragma once

$(import "error-macros.xmacro")
#include "common.x"
#include "dispatch.x"

#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <assert.h>
#include <limits.h>

/** Reports whether `tag` has a built-in encoding or registered custom row. */
int Var.known_tag(Symbol tag) =>
  _tag2id(tag) != _invalid_ || _custom_tag_id(tag) >= 0;

#pragma private
#include <string.h>
#include "symbol.x"
#include "map.x"
#include "scope.x"
#include "exception.x"
#include "string-number.x"
#include "symbolset.x"

$(import "var-tags.xmacro")

/* Symbol tags are unique but sparse. `var-tags.xmacro` assigns their dense
   IDs, coarse kinds, encoding fields, and lookups in one compile-time
   table. */
typedef enum TagId {
  _invalid_ = -1,
  $var.tag.ids(),
  _tag_count_
} TagId;

typedef struct VarTagInfo {
  Symbol tag, kind;
  unsigned long top, middle, bottom;
} VarTagInfo;

typedef struct VarDecoded {
  TagId id, int custom_id, valid;
} VarDecoded;

static const VarTagInfo taginfo[] = $var.tag.info();
static const SymbolSet tags = $var.tag.symbolset();

static TagId _tag2id(Symbol tag) => (TagId) tags.index(tag);

static inline unsigned long _bitmask(unsigned n) => (1ul << n)-1;

static inline unsigned _top_bits(Var v) {
  const unsigned long mask = _bitmask(16) << 48; // top 16 bits
  return (v.u64 & mask) >> 48;
}

static inline unsigned _middle_bits(Var v) {
  const unsigned long mask = _bitmask(16) << 32; // second 16 bits
  return (v.u64 & mask) >> 32;
}

static inline unsigned _bottom_bits(Var v) {
  const unsigned long mask = _bitmask(3); // bottom 3 bits
  return v.u64 & mask;
}

#define VAR_CUSTOM_TAG_TOP     0x800C
#define VAR_CUSTOM_TAG_COUNT   32

typedef union VarWideValue {
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
typedef struct VarWideBox {
  Symbol tag;
  VarWideValue value;
} *VarWideBox;

/* Custom IDs are the matching indices into dispatch.x's descriptor table.
   Registration is serialized with worker creation and becomes permanently
   read-only after the first successful worker start, so decoding can read
   these process-lifetime rows without a lock. IDs are never reused. */
static Symbol custom_tags[32];
static unsigned custom_tag_count;

static VarWideBox _wide_box(Var v) {
  uintptr_t raw = v.u64 & (_bitmask(48) - 0x7);
  return (VarWideBox) raw;
}

static int _custom_tag_id(Symbol tag) {
  for (unsigned i = 0; i < custom_tag_count; i++)
    if (custom_tags[i] == tag) return i;
  return -1;
}

static int _wide_encoding_valid(Var value, Symbol tag) {
  VarWideBox box = _wide_box(value);
  return box && box->tag == tag;
}

/* Wide rows validate the family recorded inside their readable box. Array and
   Map are the only built-in pointer rows whose null payload is invalid: their
   mutable empty values have allocated storage, unlike typed List nil. */
static VarDecoded _decode_builtin(TagId id, Var value) {
  int valid = 1;
  unsigned payload = (unsigned) value.u64;
  switch (id) {
    case _long_: case _ulong_: case _llong_: case _ullong_: case _ldouble_:
      valid = _wide_encoding_valid(value, taginfo[id].tag);
      break;
    case _array_: case _map_:
      valid = (value.u64 & (_bitmask(48) - 0x7)) != 0;
      break;
    case _u8_: case _i8_: valid = (payload & ~0xffu) == 0; break;
    case _u16_: case _i16_: valid = (payload & ~0xffffu) == 0; break;
    case _nan_: case _neginf_: case _posinf_:
      valid = (value.u64 & _bitmask(32)) == 0;
      break;
    default: break;
  }
  return (VarDecoded) { id, -1, valid };
}

/* `var-tags.xmacro` generates the built-in decoder. Reserved encodings report
   invalid structure and use the f64 tag and kind. */
static VarDecoded _decode(Var value) {
  unsigned top = _top_bits(value), mid = _middle_bits(value);
  unsigned btm = _bottom_bits(value);
  if (value.u64 == VAR_VOID_BITS) return (VarDecoded) { _void_, -1, 1 };
  if (value.u64 == VAR_F64_NEG_MAX_ESCAPE)
    return (VarDecoded) { _f64_, -1, 1 };
  switch (top) {
    $var.tag.decode(mid, btm);
  }
  if (top >= 0x8004 && top <= 0x800B) return (VarDecoded) { _symbol_, -1, 1 };
  if (top >= VAR_CUSTOM_TAG_TOP &&
      top < VAR_CUSTOM_TAG_TOP + VAR_CUSTOM_TAG_COUNT / 8) {
    int id = (int) ((top - VAR_CUSTOM_TAG_TOP) * 8 + btm);
    return (VarDecoded) { _invalid_, id, id < (int) custom_tag_count };
  }
  if ((top >= 0x0010 && top <= 0x7FFF) || top >= 0x8010)
    return (VarDecoded) { _f64_, -1, 1 };
  return (VarDecoded) { _f64_, -1, 0 };
}

/** Returns `value`'s dense built-in descriptor row, or `-1` when it has none.
    The row is the tag's offset from `<array>` and includes the `Symbol` row.
    Numbers, pointers, references, custom tags, and invalid encodings have no
    built-in row.
*/
int x2c_var_descriptor_index(Var value) {
  VarDecoded decoded = _decode(value);
  if (!decoded.valid || decoded.id < _array_ || decoded.id > _var_) return -1;
  return decoded.id - _array_;
}

/** Returns a registered custom object's row, or `-1` for another value. */
int Var.custom_descriptor_index(Var value) {
  VarDecoded decoded = _decode(value);
  return decoded.valid ? decoded.custom_id : -1;
}

/** Returns a built-in object or `Symbol` tag's descriptor row, or `-1`. */
int x2c_var_tag_descriptor_index(Symbol tag) {
  TagId id = _tag2id(tag);
  return id >= _array_ && id <= _var_ ? id - _array_ : -1;
}

/** Reports whether `value` has a valid structural `Var` encoding.
    An address-bearing encoding must still refer to live storage of the right
    type; wide encodings in particular require a readable `Scope`-owned box.
*/
int Var.encoding_valid(Var value) => _decode(value).valid;

/** Reserves or returns a process-lifetime row for custom boxed-object `tag`.
    Before registration freezes, a repeated custom tag returns its existing
    row; NULL, a built-in tag, or a full 32-row registry returns -1 without
    changing the registry. Registration must finish before the first successful
    `Thread.start`; afterward it raises `<bad-state>`. Native registry-mutex
    failure aborts.
*/
int Var.register_object_tag(Symbol tag) {
  x2c_descriptor_thread_start_begin();
  defer x2c_descriptor_thread_start_end(0);
  if (x2c_descriptor_registration_frozen())
    raise %(bad-state (owner "Var.register_object_tag"));
  if (!tag) return -1;
  if (_tag2id(tag) != _invalid_) return -1;
  int id = _custom_tag_id(tag);
  if (id >= 0) return id;
  if (custom_tag_count == VAR_CUSTOM_TAG_COUNT) return -1;
  custom_tags[custom_tag_count] = tag;
  return custom_tag_count++;
}

/** Returns the `Symbol` naming the exact family of `v`'s payload.
    The tag names one family: `<i32>`, `<string>`, `<f64>`, `<symbol>`, or a
    registered custom object tag. Built-in families have one row in the
    encoding table at the top of this file. Use `Var.kind` for a group of
    families and `Var.is` to test one family.

    Raw `Null`, the all-zero `Var` written `(Var) { .u64 = 0 }`, is a native
    null pointer. It decodes as `<p48>`; there is no dedicated null family.
    Test it with `Var.is_null`. An encoding matching no reserved row decodes
    as `<f64>`, since the shifted double range covers everything left over.

    ```x2c
    ~Var raw = (Var) { .u64 = 0 };
    printf("%s %s\n", raw.tag().str(), void.tag().str());
    ```
*/
Symbol Var.tag(Var v) {
  VarDecoded decoded = _decode(v);
  if (decoded.valid && decoded.custom_id >= 0)
    return custom_tags[decoded.custom_id];
  return taginfo[decoded.valid ? decoded.id : _f64_].tag;
}

/** Reports whether `value` has the requested runtime tag.
    This tests one family. A `Var` holding an `unsigned char` answers 0 for
    `<i32>` even though both are integers. When any integer will do, ask
    `Var.is_integer`, or compare `Var.kind`.
    As with `Var.tag`, validate externally constructed bits first: an invalid
    encoding uses the `<f64>` fallback.
*/
int Var.is(Var var, Symbol tag) => var.tag() == tag;

/** Returns the `Symbol` naming the coarse category of `v`'s payload.
    The categories are `<integer>`, `<floating>`, `<symbol>`, `<object>`,
    `<pointer>`, `<reference>`, and `<void>`, and every tag belongs to exactly
    one. Use kind when a group of families is treated alike. All twelve
    integer widths answer `<integer>`, and every builtin class handle such as
    `String`, `List`, `Map`, and `File` answers `<object>`.

    `<pointer>` means a raw C pointer such as `<u8*>`, while `<reference>`
    means a pointer to an object handle such as `<string*>`. NaN and the
    infinities are `<floating>`. Only `void` is `<void>`.
*/
Symbol Var.kind(Var v) {
  VarDecoded decoded = _decode(v);
  if (decoded.valid && decoded.custom_id >= 0) return <object>;
  return taginfo[decoded.valid ? decoded.id : _f64_].kind;
}

/** Reports whether `v` belongs to the floating runtime family.
    True for `<f32>`, `<f64>`, and `<ldouble>`, and for the discrete `<nan>`,
    `<+inf>`, and `<-inf>` values. Read the payload with `Var.floating`, or
    with `Var.long_double_value` when the tag is `<ldouble>` and the extra
    precision matters.
*/
int Var.is_floating(Var v)  => v.kind() == <floating>;

/** Reports whether `v` belongs to the integer runtime family.
    True for every signed and unsigned integer family from `<u8>` through
    `<ullong>`, including the scope-owned wide boxes. `Symbol`s are a kind of
    their own and answer 0 here, even though `Var.integer` returns a `Symbol`'s
    numeric value.
*/
int Var.is_integer(Var v)   => v.kind() == <integer>;

/** Reports whether `v` holds a native pointer. */
int Var.is_pointer(Var v)   => v.kind() == <pointer>;
/** Reports whether `v` holds a pointer to a boxed handle. */
int Var.is_reference(Var v) => v.kind() == <reference>;

/** Reports whether `v` holds a registered boxed object.
    True for the builtin classes such as `String`, `List`, `Array`, `Map`,
    `File`, and `Iter`, and for any tag registered with
    `Var.register_object_tag`. A
    pointer to a handle, such as `<string*>`, is `<reference>` instead and
    answers 0 here.
*/
int Var.is_object(Var v)    => v.kind() == <object>;

/** Reports whether `v` is the absence sentinel `void`.
    An API returns `void` to say there is nothing here. It is excluded from
    every collection and iterator value domain: it cannot be pushed into an
    `Array` or stored in a `Map`. Equality and identity still inspect it. Two
    sentinels compare equal and identical, while one sentinel and one
    ordinary value compare unequal. Truthiness, hashing, ordering, conversion,
    and iteration still terminate on a `void` operand.

    `Null` is the all-zero `Var`: legal collection data and false in a
    condition. A `void` result may mean missing, exhausted, or invalid;
    each API documents its meaning.

    ```x2c
    ~Var raw = (Var) { .u64 = 0 };
    printf("null: void=%d null=%d\n", raw is void, raw.is_null());
    printf("void: void=%d null=%d\n", void is void, void.is_null());
    ```

    This is the test that accepts a `void` argument.
*/
int Var.is_void(Var v)      => v.u64 == VAR_VOID_BITS;

/** Reports whether `v` is the all-zero `Null` value.
    `Null` is a value: the null pointer and the external `nil`. It is legal
    collection data, iterating a `List` can return it, and it is false in a
    condition. Its tag decodes as `<p48>`, so there is no
    dedicated null family for `Var.is` to match.

    Write `Null` as `(Var) { .u64 = 0 }`. An unresolved C `NULL` macro also
    converts to this value when its x2c target is `Var`.
*/
int Var.is_null(Var v)      => v.u64 == VAR_NULL_BITS;

/** Returns `Null`, the all-zero `Var` that stands for external `nil`.
    Generated call adapters return it for a `void` target.
*/
Var Var.null(void) {
  Var v;
  v.u64 = VAR_NULL_BITS;
  return v;
}

/** Reports whether `v` is the typed empty `List`.
    The empty `List` is a native null pointer carrying the `<list>` tag.
    `Var.is_null` answers 0 and `Var.tag` answers `<list>`. Every `%()` and
    every exhausted `List.cdr` yields this one value, so an identity test on
    the bits is a valid emptiness test.
*/
int Var.is_nil(Var v) => v.u64 == VAR_LIST_PREFIX;

static Var _new_floating(TagId id, double d) {
  Var v;
  if (id == _f32_) {
    float f = (float) d;
    unsigned u;
    memcpy(&u, &f, sizeof u);
    v.u64 = u;
    v.u64 |= (unsigned long) taginfo[id].top << 48;
    v.u64 |= (unsigned long) taginfo[id].middle << 32;
  }
  // id == _f64_
  else {
    // NaN
    if (d != d) {  // NaN test: NaN != NaN
      v.u64 = (unsigned long) taginfo[_nan_].top << 48;
      v.u64 |= (unsigned long) taginfo[_nan_].middle << 32;
    }
    // +Inf
    else if (d > 0 && d == 1.0/0.0) {
      v.u64 = (unsigned long) taginfo[_posinf_].top << 48;
      v.u64 |= (unsigned long) taginfo[_posinf_].middle << 32;
    }
    // -Inf
    else if (d < 0 && d == -1.0/0.0) {
      v.u64 = (unsigned long) taginfo[_neginf_].top << 48;
      v.u64 |= (unsigned long) taginfo[_neginf_].middle << 32;
    }
    // normal number
    else {
      unsigned long u;
      memcpy(&u, &d, sizeof u);
      if (u == VAR_F64_NEG_MAX_RAW) v.u64 = VAR_F64_NEG_MAX_ESCAPE;
      else v.u64 = u + VAR_F64_SHIFT;
    }
  }
  return v;
}

static Var _new_pointer(TagId id, void *ptr) {
  /* Pointer families store only the low 48 address bits and reclaim the
     alignment bits implied by their C type for the row subtype. */
  Var v = { .p64 = ptr };
  v.u64 |= (unsigned long) taginfo[id].top << 48;
  v.u64 |= (unsigned long) taginfo[id].bottom;
  return v;
}

static Var _new_wide(TagId id, VarWideValue value) {
  VarWideBox box = Scope.malloc(sizeof(struct VarWideBox));
  box->tag = taginfo[id].tag;
  box->value = value;
  uintptr_t raw = (uintptr_t) box;
  if ((raw & 0x7) != 0 || raw >= (1ul << 48)) {
    Scope.free(box);
    raise %(bad-enc (owner "Var.box"));
  }
  Var v = { .u64 = raw };
  v.u64 |= (unsigned long) taginfo[id].top << 48;
  v.u64 |= (unsigned long) taginfo[id].bottom;
  return v;
}

/** Boxes a `long` into a scope-owned `<long>` value.
    A `Var` is eight bytes, and the tag consumes some of them. The five widest
    native families, `long`, `unsigned long`, `long long`, `unsigned long
    long`, and `long double`, cannot be stored inline. Boxing one allocates a
    small immutable box in the active scope, and the result lives for that
    scope's lifetime like any other scope allocation.

    Two boxes of the same number are equal but not identical. On `Var`
    operands `==` is `Var.equal`, which compares payloads, while `===` is
    `Var.same`, which compares the 64 bits and therefore the box addresses.

    ```x2c
    ~Var five = Var.box_long(5L);
    ~Var also = Var.box_long(5L);
    printf("equal=%d same=%d tag=%s\n", five == also, five === also,
           five.tag().str());
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
    `<ulong>` is a distinct family from `<long>`, so a box made here never
    compares equal to one made by `Var.box_long` even when both hold the same
    bit pattern; `Var.wide_equal` requires matching tags. Read it back with
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
    The clone compares equal but not identical to `value`. Returns `void` when
    `value` is not wide.
    Raises: `<alloc-fail>` when the clone cannot be allocated, or `<bad-enc>`
    if its address cannot be represented in a `Var`.
*/
Var Var.clone_wide(Var value) {
  if (!value.is_wide()) return void;
  VarWideBox source = _wide_box(value);
  VarWideBox box = Scope.malloc(sizeof(struct VarWideBox));
  *box = *source;
  uintptr_t raw = (uintptr_t) box;
  if ((raw & 0x7) != 0 || raw >= (1ul << 48)) {
    Scope.free(box);
    raise %(bad-enc (owner "Var.clone_wide"));
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
    Ownership
    is unchanged on failure.
*/
Self Var.move_wide_to(Self value, Scope *scope) {
  if (!value.is_wide()) return value;
  Scope.move(_wide_box(value), scope);
  return value;
}

/** Returns the `Scope` owning a live wide numeric box, or NULL otherwise. */
Scope Var.wide_owner(Var value) =>
  value.is_wide() ? Scope.owner(_wide_box(value)) : NULL;

static Var _new_custom_pointer(int id, void *ptr) {
  uintptr_t raw = (uintptr_t) ptr;
  if (raw & 0x7) {
    Symbol target = custom_tags[id];
    raise %(bad-enc (owner "Var.new") (target $target));
  }
  Var v = { .u64 = raw & _bitmask(48) };
  v.u64 |= (unsigned long) (VAR_CUSTOM_TAG_TOP + id / 8) << 48;
  v.u64 |= id % 8;
  return v;
}

static Var _new_integer(TagId id, long value) {
  unsigned bits = 0;
  int is_signed = 0;
  switch (id) {
    case _u8_:  case _i8_:  bits = 8;  break;
    case _u16_: case _i16_: bits = 16; break;
    case _u32_: case _i32_: bits = 32; break;
    case _u48_: case _i48_: bits = 48; break;
    default: raise %(invariant (owner "Var.new"));
  }
  is_signed = (id == _i8_ || id == _i16_ || id == _i32_ || id == _i48_);
  unsigned long long mask = (bits == 64) ? ~0ull : ((1ull << bits) - 1ull);
  if (is_signed) {
    long long min = -(1ll << (bits - 1)), max = (1ll << (bits - 1)) - 1ll;
    if ((long long) value < min || (long long) value > max) {
      Symbol target = taginfo[id].tag;
      raise %(conv-range (owner "Var.new") (target $target));
    }
  }
  else {
    if (value < 0 || (unsigned long long) value > mask) {
      Symbol target = taginfo[id].tag;
      raise %(conv-range (owner "Var.new") (target $target));
    }
  }
  unsigned long payload = ((unsigned long) value) & (unsigned long) mask;
  Var v = { .u64 = payload };
  v.u64 |= (unsigned long) taginfo[id].top << 48;
  if (bits != 48)  v.u64 |= (unsigned long) taginfo[id].middle << 32;
  return v;
}

static Var _new_symbol(TagId id, unsigned long u) {
  static unsigned long const offset = taginfo[_symbol_].top << 48;
  if (u >= (1ul << 51)) raise %(conv-range (owner "Var.new") (target symbol));
  Var v = { .u64 = u + offset };
  return v;
}

/** Constructs a `Var` with `tag` from its tag-directed variadic payload.
    The tag chooses how the argument is read, so pass exactly the C type the
    tag names: an `int` for `<i32>`, an `unsigned long` for `<u48>`, a
    `double` for `<f64>`, a `long double` for `<ldouble>`, a pointer for any
    pointer, reference, or object family, and a `Symbol`'s numeric value for
    `<symbol>`. `<void>` consumes no payload. Variadic arguments are not
    converted for you. Assignment, `Var boxed = 42;`, is the usual way to box
    a value. Use this constructor when the tag is computed at run time.

    Immediate values are stored inline. Wide numeric tags allocate a box in the
    active `Scope`. Pointer, reference, and object tags borrow the address and
    encode only its low 48 bits; they do not take ownership, and the address
    must satisfy the alignment implied by the tag. A tag previously registered
    with `Var.register_object_tag` is accepted too and requires an 8-byte-
    aligned pointer.
    Raises: `<bad-target>` when `tag` is neither known nor registered,
    `<conv-range>` when a scalar does not fit the tag's payload width,
    `<bad-arg>` when an `<array>` or `<map>` pointer is null, `<alloc-fail>`
    when a wide box cannot be allocated, and `<bad-enc>` when a box address
    cannot be represented or a custom object pointer is not 8-byte
    aligned.
*/
Var Var.new(Symbol tag, ...) {
  va_list ap, TagId id = _tag2id(tag);
  int custom_id = id == _invalid_ ? _custom_tag_id(tag) : -1;
  if (id == _invalid_ && custom_id < 0)
    raise %(bad-target (owner "Var.new") (target $tag));
  va_start(ap, tag);
  if (custom_id >= 0) {
    Var custom = _new_custom_pointer(custom_id, va_arg(ap, void *));
    va_end(ap);
    return custom;
  }
  Var v;
  switch (taginfo[id].kind) {
    case <pointer>: case <reference>: case <object>: {
      void *pointer = va_arg(ap, void *);
      if ((id == _array_ || id == _map_) && !pointer) {
        va_end(ap);
        raise %(bad-arg (owner "Var.new") (target $tag));
      }
      v = _new_pointer(id, pointer);
      break;
    }
    case <floating>:
      if (tag == <ldouble>) v = Var.box_long_double(va_arg(ap, long double));
      else v = _new_floating(id, va_arg(ap, double));
      break;
    case <integer>:
      switch (tag) {
        case <u8>: case <i8>: case <u16>: case <i16>: case <i32>:
          v = _new_integer(id, va_arg(ap, int)); break;
        case <u32>:
          v = _new_integer(id, (long) va_arg(ap, unsigned int)); break;
        case <u48>:
          v = _new_integer(id, (long) va_arg(ap, unsigned long)); break;
        case <i48>: v = _new_integer(id, va_arg(ap, long)); break;
        case <long>: v = Var.box_long(va_arg(ap, long)); break;
        case <ulong>: v = Var.box_ulong(va_arg(ap, unsigned long)); break;
        case <llong>: v = Var.box_long_long(va_arg(ap, long long)); break;
        case <ullong>:
          v = Var.box_ulong_long(va_arg(ap, unsigned long long)); break;
      }
      break;
    case <symbol>: v = _new_symbol(id, va_arg(ap, unsigned long)); break;
    case <void>: v = void; break;
    default: va_end(ap);
      raise %(invariant (owner "Var.new") (target $tag));
  }
  va_end(ap);
  return v;
}

/** Returns `v`'s payload as a `double` when its tag is floating, or 0.0.
    Handles `<f32>`, `<f64>`, and `<ldouble>`, and reconstructs NaN,
    `+Inf`, and `-Inf` from their discrete tags. An `<ldouble>` payload is
    narrowed to `double`; call `Var.long_double_value` to keep the full
    precision.

    Like the other raw payload readers this one is silent. An integer, a
    `String`, or `void` reads as 0.0, and nothing distinguishes that from a
    stored zero. When the tag is not already known, convert with
    `Var.convert` in `lib/varconvert.x`, which raises a conversion failure;
    the scalar-named readers such as `Var.double` do this for you.

    An unhandled tag yields 0.0.
*/
double Var.floating(Var v) {
  switch (v.tag()) {
    case <f32>: case <float>: {
      unsigned u = v.u64 & _bitmask(32);
      float f;
      memcpy(&f, &u, sizeof f);
      return f;
    }
    case <f64>: case <double>: {
      unsigned long u = v.u64 == VAR_F64_NEG_MAX_ESCAPE
                      ? VAR_F64_NEG_MAX_RAW : v.u64 - VAR_F64_SHIFT;
      double d;
      memcpy(&d, &u, sizeof d);
      return d;
    }
    case <"nan">:    return  0.0 / 0.0;  // Generate NaN
    case <"-inf">:   return -1.0 / 0.0;
    case <"+inf">:   return  1.0 / 0.0;
    case <ldouble>:      return (double) _wide_box(v)->value.long_double_value;
  }
  return 0.0;
}

/** Returns `v`'s payload as a `long` when its tag is integral, or 0.
    This reads the payload; it does not convert. It decodes every integer
    family, from `<u8>` through `<ullong>`, including the scope-owned boxes, and
    returns 0 for a tag it does not handle. A `double` reads as 0, and so does
    a `String`; nothing reports the mismatch. A `<ullong>` or `<llong>`
    payload is truncated to `long`, and a `<ulong>` above `LONG_MAX` comes
    back negative. `Var.ulong_value` preserves the unsigned payload. A
    `Symbol` reads as its numeric `Symbol` value.

    When the tag might not be what you expect, convert instead of reading.
    `Var.convert` in `lib/varconvert.x` raises a conversion failure.
    Assigning a `Var` to an `int` or a `long`, and the scalar-named readers
    such as `Var.int`, go through `Var.convert` too.

    ```x2c
    ~Var text = %"ada";
    ~Var small = (unsigned char) 44;
    printf("small=%ld text=%ld\n", small.integer(), text.integer());
    ```

    An unhandled tag yields 0.
*/
long Var.integer(Var v) {
  unsigned top = _top_bits(v);
  if (top == taginfo[_u48_].top) return (unsigned long) (v.u64 & _bitmask(48));
  if (top == taginfo[_i48_].top) {
    unsigned long mask = _bitmask(48), raw = v.u64 & mask;
    if (raw & (1ul << 47)) return -(long) ((~raw & mask) + 1ul);
    return (long) raw;
  }
  if (top == taginfo[_u8_].top) {
    switch (_middle_bits(v)) {
      case 0x1: return (unsigned char)  (v.u64 & _bitmask(8));
      case 0x2: return (char)           (v.u64 & _bitmask(8));
      case 0x3: return (unsigned short) (v.u64 & _bitmask(16));
      case 0x4: return (short)          (v.u64 & _bitmask(16));
      case 0x5: return (unsigned int)   (v.u64 & _bitmask(32));
      case 0x6: return (int)            (v.u64 & _bitmask(32));
    }
  }
  if (top == 0x0005) {
    switch (_bottom_bits(v)) {
      case 0x5: return _wide_box(v)->value.long_value;
      case 0x6: return (long) _wide_box(v)->value.ulong_value;
      case 0x7: return (long) _wide_box(v)->value.long_long_value;
    }
  }
  if (top == 0x0007) {
    unsigned bottom = _bottom_bits(v);
    if (bottom == 0x6) return (long) _wide_box(v)->value.ulong_long_value;
  }
  if (top >= 0x8004 && top <= 0x800B) {
    static unsigned long const offset = taginfo[_symbol_].top << 48;
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
long Var.long_value(Var v) => v is <long> ? _wide_box(v)->value.long_value : 0;

/** Returns the payload of a `<ulong>` box, or 0 if `v` has a different tag.
    Prefer this to `Var.integer` for a `<ulong>`: the general reader casts the
    payload to `long`, which reinterprets anything above `LONG_MAX` as
    negative, while this reader returns the unsigned value. A tag that is
    not `<ulong>` yields 0 silently, so test with `Var.is` when the tag is in
    doubt.

    A tag mismatch yields 0.
*/
unsigned long Var.ulong_value(Var v) =>
  v is <ulong> ? _wide_box(v)->value.ulong_value : 0;

/** Returns an `<llong>` box's signed payload, or 0 for another tag. */
long long Var.long_long_value(Var v) =>
  v is <llong> ? _wide_box(v)->value.long_long_value : 0;

/** Returns a `<ullong>` box's unsigned payload, or 0 for another tag. */
unsigned long long Var.ulong_long_value(Var v) =>
  v is <ullong> ? _wide_box(v)->value.ulong_long_value : 0;

/** Returns the payload of an `<ldouble>` box, or 0.0 if `v` has another tag.
    This is the only reader that preserves a `long double`. Every other
    floating tag, `<f64>` included, yields 0.0 here instead of being widened.
    `Var.floating` is the general floating reader.

    A tag mismatch yields 0.0.
*/
long double Var.long_double_value(Var v) =>
  v is <ldouble> ? _wide_box(v)->value.long_double_value : 0.0L;

/* A wide box holds one or two machine words, so it mixes as words rather
   than as bytes. The tag seeds the chain, so two boxes with equal bits but
   different tags hash differently. */
static unsigned _hash_bytes(unsigned hash, void *ptr, int width) =>
  x2c_hash_bytes(hash, ptr, (size_t) width);

/** Returns a supported wide scalar box's content hash, or 0 otherwise. */
unsigned Var.wide_hash(Var v) {
  if (!v.is_wide()) return 0;
  VarWideBox box = _wide_box(v);
  Symbol tag = v.tag();
  with box->value {
    switch (tag) {
      case <long>: return _hash_bytes((unsigned) tag,
        &_.long_value, sizeof(_.long_value));
      case <ulong>: return _hash_bytes((unsigned) tag,
        &_.ulong_value, sizeof(_.ulong_value));
      case <llong>: return _hash_bytes((unsigned) tag,
        &_.long_long_value, sizeof(_.long_long_value));
      case <ullong>: return _hash_bytes((unsigned) tag,
        &_.ulong_long_value, sizeof(_.ulong_long_value));
      case <ldouble>: return _hash_bytes((unsigned) tag,
        &_.long_double_value, sizeof(_.long_double_value));
    }
  }
  return 0;
}

/** Reports content equality for supported wide scalar boxes.
    Boxed `<long>`, `<ulong>`, `<llong>`, `<ullong>`, and `<ldouble>` values
    are separate allocations, so bit identity says nothing about their
    contents. This is the payload comparison that `==` uses for those tags. An
    `<ldouble>` pair is compared byte for byte, so two NaNs sharing one
    representation compare equal here.

    A 0 result means "not equal as wide boxes". It also covers an argument
    that is not a wide box and a pair whose tags differ. For a general
    equality test use `==`, which reaches `Var.equal` and covers every
    family.
*/
int Var.wide_equal(Var a, Var b) {
  if (!a.is_wide() || !b.is_wide()) return 0;
  Symbol tag = a.tag();
  if (tag != b.tag()) return 0;
  VarWideBox abox = _wide_box(a), bbox = _wide_box(b);
  switch (tag) {
    case <long>:  return abox->value.long_value == bbox->value.long_value;
    case <ulong>:  return abox->value.ulong_value == bbox->value.ulong_value;
    case <llong>:
      return abox->value.long_long_value == bbox->value.long_long_value;
    case <ullong>:
      return abox->value.ulong_long_value == bbox->value.ulong_long_value;
    case <ldouble>: return !memcmp(
      &abox->value.long_double_value, &bbox->value.long_double_value,
      sizeof(abox->value.long_double_value));
  }
  return 0;
}

typedef struct VarIntegerParts {
  int negative;
  unsigned long long magnitude;
} VarIntegerParts;

static unsigned long long _signed_magnitude(long long value) {
  if (value >= 0) return (unsigned long long) value;
  return (unsigned long long) (-(value + 1)) + 1;
}

static VarIntegerParts _integer_parts(Var v) {
  VarIntegerParts parts = {0};
  Symbol tag = v.tag();
  switch (tag) {
    case <u8>: case <u16>: case <u32>: case <u48>:
      parts.magnitude = (unsigned long long) v.integer();
      return parts;
    case <ulong>: parts.magnitude = v.ulong_value();
      return parts;
    case <ullong>: parts.magnitude = v.ulong_long_value();
      return parts;
    case <long>: parts.negative = v.long_value() < 0;
      parts.magnitude = _signed_magnitude(v.long_value());
      return parts;
    case <llong>: parts.negative = v.long_long_value() < 0;
      parts.magnitude = _signed_magnitude(v.long_long_value());
      return parts;
    default: {
      long value = v.integer();
      parts.negative = value < 0;
      parts.magnitude = _signed_magnitude(value);
      return parts;
    }
  }
}

/** Orders the integer payloads of `a` and `b`, returning -1, 0, or 1.
    Each value is decomposed into a sign and an unsigned magnitude first, so
    the whole integer range orders correctly, including a `<ullong>` above
    `LONG_MAX` against a negative `<long>`. Subtracting in a fixed-width integer
    type could overflow.

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

static int _magnitude_floating_compare(
  unsigned long long integer, long double floating) {
  long double limit = (long double) (1ull << 63) * 2.0L;
  if (floating >= limit) return -1;
  unsigned long long floating_integer = (unsigned long long) floating;
  if (integer < floating_integer) return -1;
  if (integer > floating_integer) return 1;
  return floating == (long double) floating_integer ? 0 : -1;
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
    return -_magnitude_floating_compare(parts.magnitude, -value);
  }
  if (value < 0.0L) return 1;
  return _magnitude_floating_compare(parts.magnitude, value);
}

/** Orders two wide boxes carrying the same tag, returning -1, 0, or 1.
    Integer families delegate to `Var.integer_compare`. An `<ldouble>` pair
    compares as `long double` and falls back to a byte comparison when neither
    operand is less than the other, so distinct NaN representations still
    order deterministically.

    0 means equal, and it is also the answer for mismatched tags and for an
    argument that is not a wide box. Check the tags first, or use the
    relational operators, which reach the runtime's full ordering.
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
    &_wide_box(a)->value.long_double_value,
    &_wide_box(b)->value.long_double_value, sizeof(av));
  return cmp < 0 ? -1 : cmp > 0 ? 1 : 0;
}

/** Returns the raw address stored in `v`, or NULL if it holds no address.
    Every pointer, reference, and object family shares one decoder: the
    payload is masked free of the subtype bits its family reserves, so the
    result is the stored low-48-bit address for a `<u8*>`, a `<string>`
    handle, and a registered custom object. The returned pointer is borrowed;
    this operation does not retain it or change its lifetime. A value that is
    not address-shaped, such as an integer, a double, a `Symbol`, a wide box,
    or `void`, reads as NULL, and nothing distinguishes that from a stored
    null pointer.

    Nothing here proves that an accepted address is live or came from the
    right constructor; that remains the typed API's precondition. This raw
    decoder
    also accepts some reserved pointer-shaped bit patterns. Validate external
    bits with `Var.encoding_valid`, then confirm the family with `Var.tag` or
    `Var.is` before trusting the result.
*/
void *Var.pointer(Var v) {
  // Pointer families reserve zero, one, two, or three low subtype bits.
  unsigned top = _top_bits(v), btm = _bottom_bits(v);
  if (top <= 0x0002) return (void *) (v.u64 & _bitmask(48));
  if (top == 0x0003) return (void *) (v.u64 & (_bitmask(48) - 0x1));
  if (top == 0x0004) return (void *) (v.u64 & (_bitmask(48) - 0x3));
  if (top == 0x0005 && btm > 0x4) return NULL;
  if (top == 0x0007 && btm > 0x5) return NULL;
  if (top == 0x000B && (btm == 0x2 || btm > 0x6)) return NULL;
  if (top == 0x000F && btm > 0x6) return NULL;
  if (top >= 0x0005 && top <= 0x000F)
    return (void *) (v.u64 & (_bitmask(48) - 0x7));
  if (top >= VAR_CUSTOM_TAG_TOP &&
      top < VAR_CUSTOM_TAG_TOP + VAR_CUSTOM_TAG_COUNT / 8)
    return (void *) (v.u64 & (_bitmask(48) - 0x7));
  return NULL;
}

/** Parses `str` as source text of kind `kind` and returns the boxed value.
    The kinds understood are `<int>`, `<float>`, `<double>`, `<string>`,
    `<symbol>`, and `<char>`. For `<string>`, matching `%"..."` or `"..."`
    delimiters are removed; unquoted input is also accepted, and either form
    is unescaped. `<char>` expects `'a'` complete with its quotes and produces
    an `<i32>`. Both `<float>` and `<double>` produce an `<f64>`; there is no
    path here to `<f32>`.

    Integer and floating kinds require the whole input to parse, apart from
    surrounding whitespace. Malformed input, trailing text, a value outside
    the native reader's range, or an `<int>` outside `int` range returns
    `void`, so a parsed numeric zero remains distinguishable from failure.

    `<symbol>` accepts the leading atom or `<...>` `Symbol` literal and ignores
    trailing text; no recognized leading `Symbol` produces the zero `Symbol`. A
    kind this function does not handle returns `void`, and a bad character
    literal gives `<i32>` -1.

    ```x2c
    ~Var count = Var.parse(%"42", <int>);
    ~Var broken = Var.parse(%"abc", <int>);
    ~Var refused = Var.parse(%"3", <u8>);
    printf("%s=%s %s=%s refused=%d\n", count.tag().str(), count,
           broken.tag().str(), broken, refused is void);
    ```
    Raises: `<alloc-fail>` while constructing `String` or quoted-`Symbol`
    output.
*/
Var Var.parse(String str, Symbol kind) {
  switch (kind) {
    case <int>: {
      long value;
      if (!str.try_long(&value) || value < INT_MIN || value > INT_MAX)
        return void;
      return (int) value;
    }
    case <float>: case <double>: {
      double value;
      if (!str.try_double(&value)) return void;
      return value;
    }
    case <string>:    return str.parse();
    case <symbol>:    return Symbol.parse(str);
    case <char>:      return str.parse_char();
    default:          return void;
  }
}
