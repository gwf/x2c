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
    800C:0000:0000:0000 - 800F:FFFF:FFFF:FFFF  45+3  user (Class)* 30,
                                                      overflow cell,
                                                      overflow record
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

/** Names the built-in `Var` tags in `var-tags.xmacro` ledger order, which
    is the order of `x2c_var_taginfo`; `lib/var-ledger.x` checks the two
    agree. */
typedef enum TagId {
  _invalid_ = -1,
  _u8_, _i8_, _u16_, _i16_, _u32_, _i32_, _f32_, _u48_, _i48_, _p48_, _f64_,
  _long_, _ulong_, _llong_, _ullong_, _ldouble_, _u8_p_, _i8_p_, _u16_p_,
  _i16_p_, _u32_p_, _i32_p_, _f32_p_, _ulong_p_, _long_p_, _f64_p_,
  _ullong_p_, _llong_p_, _ldouble_p_, _p48_p_, _u8_pp_, _i8_pp_, _u16_pp_,
  _i16_pp_, _u32_pp_, _i32_pp_, _f32_pp_, _ulong_pp_, _long_pp_, _f64_pp_,
  _ullong_pp_, _llong_pp_, _ldouble_pp_, _array_, _block_, _buffer_, _bytes_,
  _context_, _error_, _file_, _func_, _iter_, _lambda_, _list_, _logger_,
  _map_, _mutex_, _pipe_, _proc_, _regexp_, _rope_, _scope_, _slice_,
  _socket_, _stream_, _string_, _symbol_, _tensor_, _thread_, _token_, _var_,
  _array_p_, _block_p_, _buffer_p_, _bytes_p_, _context_p_, _error_p_,
  _file_p_, _func_p_, _iter_p_, _lambda_p_, _list_p_, _logger_p_, _map_p_,
  _mutex_p_, _pipe_p_, _proc_p_, _regexp_p_, _rope_p_, _scope_p_, _slice_p_,
  _socket_p_, _stream_p_, _string_p_, _symbol_p_, _tensor_p_, _thread_p_,
  _token_p_, _var_p_, _nan_, _neginf_, _posinf_, _void_,
  _tag_count_
} TagId;

/** Describes one built-in `Var` tag's kind and encoding fields. */
typedef struct VarTagInfo {
  Symbol tag, kind;
  unsigned long top, middle, bottom;
} VarTagInfo;

/** Resolves one encoding top: the selector is the middle field when
    `by_middle` is set and the bottom field under `mask` otherwise, and
    `ids` maps it to a `TagId`, or `_invalid_` where no tag has it. */
typedef struct VarDecodeGroup {
  unsigned char mask, by_middle;
  signed char ids[8];
} VarDecodeGroup;

/** Reports whether `tag` has a built-in encoding or declared custom class. */
int Var.known_tag(Symbol tag) =>
  _tag2id(tag) != _invalid_ || _declared(tag) != NULL;

#pragma private
#include <string.h>
#include "symbol.x"
#include "map.x"
#include "scope.x"
#include "exception.x"
#include "string-number.x"
#include "symbolset.x"

// encoding fields

/* `lib/var-ledger.x` projects the tag tables and the decoder's group table
   from the ledger in `var-tags.xmacro`. */
typedef struct VarDecoded {
  TagId id, int custom_id, valid;
} VarDecoded;

extern const VarTagInfo x2c_var_taginfo[];
extern const SymbolSet x2c_var_tags;
extern const VarDecodeGroup x2c_var_decode_groups[];

static TagId _tag2id(Symbol tag) => (TagId) x2c_var_tags.index(tag);

static inline unsigned long _bitmask(unsigned n) => (1ul << n) - 1;

static inline unsigned _top_bits(Var v)    => v.u64 >> 48;
static inline unsigned _middle_bits(Var v) => (v.u64 >> 32) & _bitmask(16);
static inline unsigned _bottom_bits(Var v) => v.u64 & _bitmask(3);

static void *_address(Var value) =>
  (void *) (value.u64 & (_bitmask(48) - 0x7));

/** Returns the top encoding field of built-in `tag`. */
meta native unsigned long Var.tag_top(Symbol tag) {
  TagId id = _tag2id(tag);
  if (id == _invalid_) raise %(bad-target (owner "Var.tag_top") (target $tag));
  return x2c_var_taginfo[id].top;
}

/** Returns the bottom encoding field of built-in `tag`. */
meta native unsigned long Var.tag_bottom(Symbol tag) {
  TagId id = _tag2id(tag);
  if (id == _invalid_)
    raise %(bad-target (owner "Var.tag_bottom") (target $tag));
  return x2c_var_taginfo[id].bottom;
}

// wide boxes

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

static VarWideBox _wide_box(Var v) => (VarWideBox) _address(v);

// custom classes

#define VAR_CUSTOM_TAG_TOP     0x800C
#define VAR_CUSTOM_TAG_COUNT   32
#define VAR_DIRECT_ROWS        30
#define VAR_CELL_ROW           30
#define VAR_RECORD_ROW         31
#define VAR_CELL_MASK          0xFFFF000000000007ul
#define VAR_CELL_BITS          0x800F000000000006ul

/* Declaring a custom class adds its descriptor to `declared` under the
   descriptor mutex; declaration freezes at the first successful worker
   start, so later lookups read the Map without a lock. The first box of a
   class assigns the next direct row under the same mutex. Rows are
   append-only: a slot is written before `row_count` is published with a
   release store, and every reader loads the count with acquire. Classes past
   the direct rows box through a cell (heap classes) or a descriptor prefix
   (records), and both carry their descriptor. */
static Scope class_scope;
static Map declared;
static VarDescriptor *rows[VAR_DIRECT_ROWS];
static unsigned row_count;

/* An overflow heap class boxes the one process-lifetime cell for its class
   and address, so boxing an object twice gives identical bits. `cells` maps
   an address to its cells, one per class, chained through `next`. */
typedef struct VarCell {
  VarDescriptor *descriptor;
  void *pointer;
  struct VarCell *next;
} VarCell;

static Map cells;

/* An overflow record keeps its descriptor in one aligned slot in front of
   the boxed copy, as Scope keeps its metadata in front of each payload. */
#define RECORD_PREFIX sizeof(max_align_t)

static VarDescriptor *_declared(Symbol tag) {
  if (declared == NULL) return NULL;
  Var found = declared[tag];
  return found is void ? NULL : found.pointer();
}

static unsigned _row_count(void) =>
  __atomic_load_n(&row_count, __ATOMIC_ACQUIRE);

static VarDescriptor *_row_descriptor(int id, Var value) {
  if (id == VAR_CELL_ROW) return ((VarCell *) _address(value)).descriptor;
  if (id == VAR_RECORD_ROW)
    return *(VarDescriptor **) ((char *) _address(value) - RECORD_PREFIX);
  return rows[id];
}

/* The four custom tops hold 32 rows, eight to a top in the bottom bits. A
   direct row is valid once assigned; an overflow row needs the address of
   its cell or record. */
static inline int _custom_top(unsigned top) =>
  top >= VAR_CUSTOM_TAG_TOP &&
  top < VAR_CUSTOM_TAG_TOP + VAR_CUSTOM_TAG_COUNT / 8;

static inline int _custom_id(unsigned top, unsigned bottom) =>
  (int) ((top - VAR_CUSTOM_TAG_TOP) * 8 + bottom);

static inline int _custom_valid(int id, Var value) =>
  id < VAR_DIRECT_ROWS ? id < (int) _row_count() : _address(value) != NULL;

// decoding

/* The ledger's group table resolves the pointer, object, and immediate tops.
   Reserved encodings report invalid structure and use the f64 tag and kind.
*/
static VarDecoded _decode(Var value) {
  unsigned top = _top_bits(value), btm = _bottom_bits(value);
  if (value.u64 == VAR_VOID_BITS) return (VarDecoded) { _void_, -1, 1 };
  if (value.u64 == VAR_F64_NEG_MAX_ESCAPE)
    return (VarDecoded) { _f64_, -1, 1 };
  int id = _group_id(top, _middle_bits(value), btm);
  if (id != _invalid_) return _decode_builtin((TagId) id, value);
  if (top >= 0x8004 && top <= 0x800B) return (VarDecoded) { _symbol_, -1, 1 };
  if (_custom_top(top)) {
    int custom = _custom_id(top, btm);
    return (VarDecoded) { _invalid_, custom, _custom_valid(custom, value) };
  }
  if ((top >= 0x0010 && top <= 0x7FFF) || top >= 0x8010)
    return (VarDecoded) { _f64_, -1, 1 };
  return (VarDecoded) { _f64_, -1, 0 };
}

/* Rotating the top left one bit puts 0x0000-0x000F on the even slots and
   0x8000-0x800F on the odd slots below 32; every other top lands above. */
static inline int _group_id(unsigned top, unsigned mid, unsigned btm) {
  unsigned slot = ((top << 1) | (top >> 15)) & 0xFFFF;
  if (slot >= 32) return _invalid_;
  const VarDecodeGroup *group = &x2c_var_decode_groups[slot];
  unsigned selector = group.by_middle ? mid : btm & group.mask;
  return selector < 8 ? group.ids[selector] : _invalid_;
}

/* Wide rows validate the family recorded inside their readable box. Array and
   Map are the only built-in pointer rows whose null payload is invalid: their
   mutable empty values have allocated storage, unlike typed List nil. */
static VarDecoded _decode_builtin(TagId id, Var value) {
  int valid = 1;
  unsigned payload = (unsigned) value.u64;
  switch (id) {
    case _long_: case _ulong_: case _llong_: case _ullong_: case _ldouble_:
      valid = _wide_encoding_valid(value, x2c_var_taginfo[id].tag);
      break;
    case _array_: case _map_: valid = _address(value) != NULL; break;
    case _u8_: case _i8_: valid = (payload & ~0xffu) == 0; break;
    case _u16_: case _i16_: valid = (payload & ~0xffffu) == 0; break;
    case _nan_: case _neginf_: case _posinf_:
      valid = (value.u64 & _bitmask(32)) == 0;
      break;
    default: break;
  }
  return (VarDecoded) { id, -1, valid };
}

static int _wide_encoding_valid(Var value, Symbol tag) {
  VarWideBox box = _wide_box(value);
  return box && box.tag == tag;
}

// tags and kinds

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
meta native Symbol Var.tag(Var v) {
  VarDecoded decoded = _decode(v);
  if (decoded.valid && decoded.custom_id >= 0)
    return _row_descriptor(decoded.custom_id, v).tag;
  return x2c_var_taginfo[decoded.valid ? decoded.id : _f64_].tag;
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
meta native Symbol Var.kind(Var v) {
  VarDecoded decoded = _decode(v);
  if (decoded.valid && decoded.custom_id >= 0) return <object>;
  return x2c_var_taginfo[decoded.valid ? decoded.id : _f64_].kind;
}

/** Reports whether `v` belongs to the floating runtime family.
    True for `<f32>`, `<f64>`, and `<ldouble>`, and for the discrete `<nan>`,
    `<+inf>`, and `<-inf>` values. Read the payload with `Var.floating`, or
    with `Var.long_double_value` when the tag is `<ldouble>` and the extra
    precision matters.
*/
meta native int Var.is_floating(Var v)  => v.kind() == <floating>;

/** Reports whether `v` belongs to the integer runtime family.
    True for every signed and unsigned integer family from `<u8>` through
    `<ullong>`, including the scope-owned wide boxes. `Symbol`s are a kind of
    their own and answer 0 here, even though `Var.integer` returns a `Symbol`'s
    numeric value.
*/
int Var.is_integer(Var v)   => v.kind() == <integer>;

/** Reports whether `v` holds a native pointer. */
meta native int Var.is_pointer(Var v)   => v.kind() == <pointer>;

/** Reports whether `v` holds a pointer to a boxed handle. */
meta native int Var.is_reference(Var v) => v.kind() == <reference>;

/** Reports whether `v` holds a registered boxed object.
    True for the builtin classes such as `String`, `List`, `Array`, `Map`,
    `File`, and `Iter`, and for any tag registered with
    `Var.register_object_tag`. A pointer to a handle, such as `<string*>`, is
    `<reference>` instead and answers 0 here.
*/
meta native int Var.is_object(Var v)    => v.kind() == <object>;

/** Reports whether `v` is the absence sentinel `void`.
    An API returns `void` to say there is nothing here. It is excluded from
    every collection and iterator value domain: it cannot be pushed into an
    `Array` or stored in a `Map`. Equality and identity still inspect it. Two
    sentinels compare equal and identical, while one sentinel and one
    ordinary value compare unequal. Truthiness, hashing, ordering, conversion,
    and iteration on `void` raise to a matching catch or terminate.

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
    condition. Its tag decodes as `<p48>`, so there is no dedicated null
    family for `Var.is` to match.

    Write `Null` as `(Var) { .u64 = 0 }`. An unresolved C `NULL` macro also
    converts to this value when its x2c target is `Var`.
*/
meta native int Var.is_null(Var v)      => v.u64 == VAR_NULL_BITS;

/** Returns `Null`, the all-zero `Var` that stands for external `nil`.
    Generated call adapters return it for a `void` target.
*/
meta native Var Var.null(void) => (Var) { .u64 = VAR_NULL_BITS };

/** Reports whether `v` is the typed empty `List`.
    The empty `List` is a native null pointer carrying the `<list>` tag.
    `Var.is_null` answers 0 and `Var.tag` answers `<list>`. Every `%()` and
    every exhausted `List.cdr` yields this one value, so an identity test on
    the bits is a valid emptiness test.
*/
meta native int Var.is_nil(Var v) => v.u64 == VAR_LIST_PREFIX;

/** Reports whether `value` has a valid structural `Var` encoding.
    An address-bearing encoding must still refer to live storage of the right
    type; wide encodings in particular require a readable `Scope`-owned box.
*/
int Var.encoding_valid(Var value) => _decode(value).valid;

// descriptor rows

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

/** Returns a boxed custom object's row, or `-1` for another value.
    Rows below 30 belong to one class each; row 30 holds every overflow heap
    class and row 31 every overflow record.
*/
int Var.custom_descriptor_index(Var value) {
  VarDecoded decoded = _decode(value);
  return decoded.valid ? decoded.custom_id : -1;
}

/** Returns a boxed custom object's descriptor, or NULL for another value. */
VarDescriptor *x2c_var_custom_descriptor(Var value) {
  unsigned top = _top_bits(value);
  if (!_custom_top(top)) return NULL;
  int id = _custom_id(top, _bottom_bits(value));
  if (id < VAR_DIRECT_ROWS) return id < (int) _row_count() ? rows[id] : NULL;
  return _address(value) ? _row_descriptor(id, value) : NULL;
}

/** Returns a built-in object or `Symbol` tag's descriptor row, or `-1`. */
int x2c_var_tag_descriptor_index(Symbol tag) {
  TagId id = _tag2id(tag);
  return id >= _array_ && id <= _var_ ? id - _array_ : -1;
}

// construction

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
    must satisfy the alignment implied by the tag. A declared custom tag is
    accepted too and requires an 8-byte-aligned pointer. Once the direct
    custom rows are taken, a custom object boxes through a process-lifetime
    cell, one per class and address, so boxing one object twice gives
    identical bits.
    Raises: `<bad-target>` when `tag` is neither known nor registered,
    `<conv-range>` when a scalar does not fit the tag's payload width,
    `<bad-arg>` when an `<array>` or `<map>` pointer is null, `<alloc-fail>`
    when a wide box cannot be allocated, and `<bad-enc>` when a box address
    cannot be represented or a custom object pointer is not 8-byte
    aligned.
*/
Var Var.new(Symbol tag, ...) {
  va_list ap, TagId id = _tag2id(tag);
  VarDescriptor *descriptor = NULL;
  int row = id == _invalid_ ? _custom_row(tag, descriptor) : -1;
  if (id == _invalid_ && row < 0)
    raise %(bad-target (owner "Var.new") (target $tag));
  va_start(ap, tag);
  if (row >= 0) {
    void *pointer = va_arg(ap, void *);
    va_end(ap);
    if ((uintptr_t) pointer & 0x7)
      raise %(bad-enc (owner "Var.new") (target $tag));
    if (row < VAR_DIRECT_ROWS) return _new_custom_pointer(row, pointer);
    return _new_custom_pointer(VAR_CELL_ROW, _cell(descriptor, pointer));
  }
  Var v = _new_builtin(id, tag, ap);
  va_end(ap);
  return v;
}

/* The row's kind names the C type of the one variadic payload. */
static Var _new_builtin(TagId id, Symbol tag, va_list ap) {
  switch (x2c_var_taginfo[id].kind) {
    case <pointer>: case <reference>: case <object>:
      return _new_pointer(id, va_arg(ap, void *));
    case <floating>: return _floating_arg(id, tag, ap);
    case <integer>:  return _integer_arg(id, tag, ap);
    case <symbol>:   return _new_symbol(va_arg(ap, unsigned long));
    case <void>:     return void;
  }
  raise %(invariant (owner "Var.new") (target $tag));
}

/* Pointer families store only the low 48 address bits and reclaim the
   alignment bits implied by their C type for the row subtype. Array and Map
   are the only rows whose null payload is invalid. */
static Var _new_pointer(TagId id, void *ptr) {
  if ((id == _array_ || id == _map_) && !ptr) {
    Symbol tag = x2c_var_taginfo[id].tag;
    raise %(bad-arg (owner "Var.new") (target $tag));
  }
  Var v = { .p64 = ptr };
  v.u64 |= x2c_var_taginfo[id].top << 48;
  v.u64 |= x2c_var_taginfo[id].bottom;
  return v;
}

/* `<f32>` arrives promoted to `double`, and the discrete NaN and infinity
   tags box their payload as an `<f64>`. */
static Var _floating_arg(TagId id, Symbol tag, va_list ap) {
  if (tag == <ldouble>) return Var.box_long_double(va_arg(ap, long double));
  double d = va_arg(ap, double);
  return id == _f32_ ? Var.box_f32((float) d) : Var.box_f64(d);
}

/* Tags up to 32 bits arrive promoted to `int` or `unsigned int`, and
   `<ullong>` is the one integer row the switch leaves. */
static Var _integer_arg(TagId id, Symbol tag, va_list ap) {
  switch (tag) {
    case <u8>: case <i8>: case <u16>: case <i16>: case <i32>:
      return _new_integer(id, va_arg(ap, int));
    case <u32>:   return _new_integer(id, (long) va_arg(ap, unsigned int));
    case <u48>:   return _new_integer(id, (long) va_arg(ap, unsigned long));
    case <i48>:   return _new_integer(id, va_arg(ap, long));
    case <long>:  return Var.box_long(va_arg(ap, long));
    case <ulong>: return Var.box_ulong(va_arg(ap, unsigned long));
    case <llong>: return Var.box_long_long(va_arg(ap, long long));
  }
  return Var.box_ulong_long(va_arg(ap, unsigned long long));
}

/* An immediate integer keeps its tag's width of payload bits. The 48-bit
   rows carry no middle field. */
static Var _new_integer(TagId id, long value) {
  unsigned bits = _integer_width(id);
  if (!_integer_fits(id, value, bits)) {
    Symbol target = x2c_var_taginfo[id].tag;
    raise %(conv-range (owner "Var.new") (target $target));
  }
  Var v = { .u64 = (unsigned long) value & _bitmask(bits) };
  v.u64 |= x2c_var_taginfo[id].top << 48;
  if (bits != 48) v.u64 |= x2c_var_taginfo[id].middle << 32;
  return v;
}

static unsigned _integer_width(TagId id) {
  switch (id) {
    case _u8_:  case _i8_:  return 8;
    case _u16_: case _i16_: return 16;
    case _u32_: case _i32_: return 32;
    case _u48_: case _i48_: return 48;
    default: raise %(invariant (owner "Var.new"));
  }
}

static int _integer_fits(TagId id, long value, unsigned bits) {
  if (id == _i8_ || id == _i16_ || id == _i32_ || id == _i48_) {
    long long bound = 1ll << (bits - 1);
    return value >= -bound && value < bound;
  }
  return value >= 0 && (unsigned long) value <= _bitmask(bits);
}

static Var _new_symbol(unsigned long u) {
  if (u >= (1ul << 51)) raise %(conv-range (owner "Var.new") (target symbol));
  return (Var) { .u64 = u + VAR_SYMBOL_OFFSET };
}

// custom objects

/** Boxes a copy of the `size`-byte record at `record` as custom `tag`.
    The copy is allocated in the active `Scope`. Once the direct custom rows
    are taken, the copy carries its descriptor in front of it.
    Raises: `<bad-target>` when `tag` names no declared class, or
    `<alloc-fail>` when the copy cannot be allocated.
*/
Var Var.box_record(Symbol tag, const void *record, size_t size) {
  VarDescriptor *descriptor = NULL;
  int row = _custom_row(tag, descriptor);
  if (row < 0) raise %(bad-target (owner "Var.box_record") (target $tag));
  if (row < VAR_DIRECT_ROWS)
    return _new_custom_pointer(row, Scope.memdup(record, size));
  char *copy = Scope.malloc(RECORD_PREFIX + size);
  *(VarDescriptor **) copy = descriptor;
  memcpy(copy + RECORD_PREFIX, record, size);
  return _new_custom_pointer(VAR_RECORD_ROW, copy + RECORD_PREFIX);
}

/* Returns custom `tag`'s row, assigning it on first box, or -1 when `tag`
   names no declared class. Sets `descriptor` for a declared class that has
   no direct row. */
static int _custom_row(Symbol tag, VarDescriptor *&descriptor) {
  unsigned count = _row_count();
  for (unsigned i = 0; i < count; i++) if (rows[i].tag == tag) return (int) i;
  descriptor = _declared(tag);
  return descriptor ? _assign_row(descriptor) : -1;
}

/* Assigns `descriptor` its row on first box: the next direct row while one
   is free, otherwise the overflow rows. */
static int _assign_row(VarDescriptor *descriptor) {
  int row = __atomic_load_n(&descriptor.row, __ATOMIC_ACQUIRE);
  if (row >= 0) return row;
  x2c_descriptor_thread_start_begin();
  defer x2c_descriptor_thread_start_end(0);
  row = descriptor.row;
  if (row >= 0) return row;
  unsigned count = row_count;
  row = count < VAR_DIRECT_ROWS ? (int) count : VAR_CELL_ROW;
  if (count < VAR_DIRECT_ROWS) {
    rows[count] = descriptor;
    __atomic_store_n(&row_count, count + 1, __ATOMIC_RELEASE);
  }
  __atomic_store_n(&descriptor.row, row, __ATOMIC_RELEASE);
  return row;
}

static VarCell *_cell(VarDescriptor *descriptor, void *pointer) {
  x2c_descriptor_thread_start_begin();
  defer x2c_descriptor_thread_start_end(0);
  Var key = { .p64 = pointer };
  VarCell *cell = NULL;
  $scope(&class_scope) {
    if (cells == NULL) cells = {};
    Var head = cells[key];
    VarCell *first = head is void ? NULL : head.pointer();
    cell = first;
    while (cell && cell.descriptor != descriptor) cell = cell.next;
    if (!cell) {
      cell = Scope.malloc(sizeof(VarCell));
      *cell = (VarCell) { descriptor, pointer, first };
      cells[key] = (void *) cell;
    }
  }
  return cell;
}

static Var _new_custom_pointer(int id, void *ptr) {
  uintptr_t raw = (uintptr_t) ptr;
  Var v = { .u64 = raw & _bitmask(48) };
  v.u64 |= (unsigned long) (VAR_CUSTOM_TAG_TOP + id / 8) << 48;
  v.u64 |= id % 8;
  return v;
}

// wide scalars

static Var _new_wide(TagId id, VarWideValue value) {
  VarWideBox box = Scope.malloc(sizeof(struct VarWideBox));
  box.tag = x2c_var_taginfo[id].tag;
  box.value = value;
  uintptr_t raw = (uintptr_t) box;
  if ((raw & 0x7) != 0 || raw >= (1ul << 48)) {
    Scope.free(box);
    raise %(bad-enc (owner "Var.box"));
  }
  Var v = { .u64 = raw };
  v.u64 |= x2c_var_taginfo[id].top << 48;
  v.u64 |= x2c_var_taginfo[id].bottom;
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
meta native Var Var.clone_wide(Var value) {
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
    `Var.convert` in `lib/varconvert.x`, which raises a conversion failure;
    the scalar-named readers such as `Var.double` do this for you.

    An unhandled tag yields 0.0.
*/
meta native double Var.floating(Var v) {
  switch (v.tag()) {
    case <f32>: case <float>:  return v.decode_f32();
    case <f64>: case <double>: return _f64_floating(v);
    case <"nan">:   return  0.0 / 0.0;
    case <"-inf">:  return -1.0 / 0.0;
    case <"+inf">:  return  1.0 / 0.0;
    case <ldouble>: return (double) _wide_box(v).value.long_double_value;
  }
  return 0.0;
}

/* `Var.decode_f64` would first test the NaN and infinity patterns, which an
   `<f64>` tag has already excluded. */
static double _f64_floating(Var v) {
  unsigned long u = v.u64 == VAR_F64_NEG_MAX_ESCAPE
                  ? VAR_F64_NEG_MAX_RAW : v.u64 - VAR_F64_SHIFT;
  double d;
  memcpy(&d, &u, sizeof d);
  return d;
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
    `Var.convert` in `lib/varconvert.x` raises a conversion failure.
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
  if (top == x2c_var_taginfo[_u8_].top) return _narrow_integer(v);
  if (top == 0x0005) return _wide_integer(v);
  if (top == 0x0007 && _bottom_bits(v) == 0x6)
    return (long) _wide_box(v).value.ulong_long_value;
  if (top >= 0x8004 && top <= 0x800B)
    return (Symbol) (v.u64 - VAR_SYMBOL_OFFSET);
  return 0;
}

static long _i48_integer(Var v) {
  unsigned long mask = _bitmask(48), raw = v.u64 & mask;
  if (raw & (1ul << 47)) return -(long) ((~raw & mask) + 1ul);
  return (long) raw;
}

/* The 8-, 16-, and 32-bit rows share one top and differ in the middle. */
static long _narrow_integer(Var v) {
  switch (_middle_bits(v)) {
    case 0x1: return (unsigned char)  (v.u64 & _bitmask(8));
    case 0x2: return (char)           (v.u64 & _bitmask(8));
    case 0x3: return (unsigned short) (v.u64 & _bitmask(16));
    case 0x4: return (short)          (v.u64 & _bitmask(16));
    case 0x5: return (unsigned int)   (v.u64 & _bitmask(32));
    case 0x6: return (int)            (v.u64 & _bitmask(32));
  }
  return 0;
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

/** Returns the payload of an `<ldouble>` box, or 0.0 if `v` has another tag.
    This is the only reader that preserves a `long double`. Every other
    floating tag, `<f64>` included, yields 0.0 here instead of being widened.
    `Var.floating` is the general floating reader.

    A tag mismatch yields 0.0.
*/
meta native long double Var.long_double_value(Var v) =>
  v is <ldouble> ? _wide_box(v).value.long_double_value : 0.0L;

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
    decoder also accepts some reserved pointer-shaped bit patterns. Validate
    external bits with `Var.encoding_valid`, then confirm the family with
    `Var.tag` or `Var.is` before trusting the result.
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
  if (top >= 0x0005 && top <= 0x000F) return _address(v);
  if ((v.u64 & VAR_CELL_MASK) == VAR_CELL_BITS)
    return ((VarCell *) _address(v)).pointer;
  if (_custom_top(top)) return _address(v);
  return NULL;
}

/* wide equality

   A wide box holds one or two machine words, so it mixes as words rather
   than as bytes. The tag seeds the chain, so two boxes with equal bits but
   different tags hash differently. */

/** Returns a supported wide scalar box's content hash, or 0 otherwise. */
unsigned Var.wide_hash(Var v) {
  if (!v.is_wide()) return 0;
  VarWideBox box = _wide_box(v);
  Symbol tag = v.tag();
  size_t width = _wide_width(tag);
  return width ? x2c_hash_bytes((unsigned) tag, &box.value, width) : 0;
}

/* The payload bytes of a wide family. Every member of the box's union
   starts at the union, so the payload is the union's first `width` bytes. */
static size_t _wide_width(Symbol tag) {
  switch (tag) {
    case <long>:    return sizeof(long);
    case <ulong>:   return sizeof(unsigned long);
    case <llong>:   return sizeof(long long);
    case <ullong>:  return sizeof(unsigned long long);
    case <ldouble>: return sizeof(long double);
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

// ordering

typedef struct VarIntegerParts {
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
    &_wide_box(a).value.long_double_value,
    &_wide_box(b).value.long_double_value, sizeof(av));
  return cmp < 0 ? -1 : cmp > 0 ? 1 : 0;
}

// parsing

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
    ~Var count = Var.parse("42", <int>);
    ~Var broken = Var.parse("abc", <int>);
    ~Var refused = Var.parse("3", <u8>);
    printf("%s=%s %s=%s refused=%d\n", count.tag().str(), count,
           broken.tag().str(), broken, refused is void);
    ```
    Raises: `<alloc-fail>` while constructing `String` or quoted-`Symbol`
    output.
*/
meta native Var Var.parse(String str, Symbol kind) {
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

// class registration

/** Declares custom boxed-object `tag` and returns 0.
    Declaring spends no `Var` row; the first box of a value assigns one.
    Declaring a tag again returns 0; NULL or a built-in tag returns -1 without
    changing the registry. Declaration must finish before the first successful
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
  x2c_var_declare(tag);
  return 0;
}

/** Returns the process-lifetime descriptor declared for custom `tag`,
    declaring it on first use. The caller holds the descriptor lock and has
    checked that registration is open and `tag` is not built in.
*/
VarDescriptor *x2c_var_declare(Symbol tag) {
  VarDescriptor *descriptor = _declared(tag);
  if (descriptor) return descriptor;
  if (!class_scope) {
    class_scope = Scope.new_named("Var classes");
    Scope.shutdown_hook(_classes_shutdown);
  }
  $scope(&class_scope) {
    if (declared == NULL) declared = {};
    descriptor = Scope.calloc(1, sizeof(VarDescriptor));
    descriptor.tag = tag;
    descriptor.row = -1;
    declared[tag] = (void *) descriptor;
  }
  return descriptor;
}

static void _classes_shutdown(void) {
  class_scope.destroy();
  class_scope = NULL;
  declared = cells = NULL;
  row_count = 0;
}
