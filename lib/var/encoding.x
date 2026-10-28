/*  encoding.x -- Var encoding and classification */

/* encoding fields

   The layout uses the IEEE 754 double-precision ranges:

   0000:0000:0000:0000 - 7FEF:FFFF:FFFF:FFFF : [+0.0, MAX_DOUBLE]
   7FF0:0000:0000:0000 - 7FFF:FFFF:FFFF:FFFF : [+Inf, +NaNs]
   8000:0000:0000:0000 - FFEF:FFFF:FFFF:FFFF : [-0.0, MIN_DOUBLE]
   FFF0:0000:0000:0000 - FFFF:FFFF:FFFF:FFFF : [-Inf, -NaNs]

   Special-value ranges carry custom tags and payloads. An f64 is shifted by
   (1 << 52); shifted -DBL_MAX has a reserved encoding because all-one bits
   mean `void`. Native pointers retain their raw lower 48 address bits.

   Tag : Payload         Tag : Payload        bits  Use

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
*/

/* `lib/var-ledger.x` projects the tag tables and the decoder's group table
   from the ledger in `var-tags.x`. */
static typedef struct VarDecoded {
  TagId id, int custom_id, valid;
} VarDecoded;

/** Returns the top encoding field of built-in `tag`. */
meta native unsigned long Var.tag_top(Symbol tag) {
  TagId id = _tag2id(tag);
  if (id == _invalid_)
    raise %(bad-target (operation "Var.tag_top") (target $tag));
  return x2c_var_taginfo[id].top;
}

/** Returns the bottom encoding field of built-in `tag`. */
meta native unsigned long Var.tag_bottom(Symbol tag) {
  TagId id = _tag2id(tag);
  if (id == _invalid_)
    raise %(bad-target (operation "Var.tag_bottom") (target $tag));
  return x2c_var_taginfo[id].bottom;
}

// tags and kinds

/** Reports whether `value` has the requested runtime tag.
    This tests one family. For a `Var` holding an `unsigned char`, this returns
    0 for `<i32>` even though both are integers. When any integer will do, use
    `Var.is_integer`, or compare `Var.kind`.
    As with `Var.tag`, validate externally constructed bits first: an invalid
    encoding uses the `<f64>` fallback.
*/
int Var.is(Var var, Symbol tag) => var.tag() == tag;



/** Returns the `Symbol` naming the exact family of `v`'s payload.
    The tag names one family: `<i32>`, `<string>`, `<f64>`, `<symbol>`, or a
    registered custom object tag. Built-in families have one row in the
    encoding table in this file. Use `Var.kind` for a group of
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
    their own, so this returns 0 for them, even though `Var.integer` returns a
    `Symbol`'s numeric value.
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
    `<reference>` instead, so this returns 0 for it.
*/
meta native int Var.is_object(Var v)    => v.kind() == <object>;

/** Returns the `Symbol` naming the coarse category of `v`'s payload.
    The categories are `<integer>`, `<floating>`, `<symbol>`, `<object>`,
    `<pointer>`, `<reference>`, and `<void>`, and every tag belongs to exactly
    one. Use kind when a group of families is treated alike. This returns
    `<integer>` for all twelve integer widths and `<object>` for every builtin
    class handle such as `String`, `List`, `Map`, and `File`.

    `<pointer>` means a raw C pointer such as `<u8*>`, while `<reference>`
    means a pointer to an object handle such as `<string*>`. NaN and the
    infinities are `<floating>`. Only `void` is `<void>`.
*/
meta native Symbol Var.kind(Var v) {
  VarDecoded decoded = _decode(v);
  if (decoded.valid && decoded.custom_id >= 0) return <object>;
  return x2c_var_taginfo[decoded.valid ? decoded.id : _f64_].kind;
}

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
    `Var.is_null` returns 0 and `Var.tag` returns `<list>`. Every `%()` and
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

/** Returns a built-in object or `Symbol` tag's descriptor row, or `-1`. */
int x2c_var_tag_descriptor_index(Symbol tag) {
  TagId id = _tag2id(tag);
  return id >= _array_ && id <= _var_ ? id - _array_ : -1;
}

module TagId _tag2id(Symbol tag) => (TagId) x2c_var_tags.index(tag);

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

module inline unsigned _top_bits(Var v)    => v.u64 >> 48;

module inline unsigned _middle_bits(Var v) => (v.u64 >> 32) & _bitmask(16);

module inline unsigned _bottom_bits(Var v) => v.u64 & _bitmask(3);

static inline int _group_id(unsigned top, unsigned mid, unsigned btm) {
  unsigned slot = _group_slot(top);
  if (slot >= 32) return _invalid_;
  const VarDecodeGroup *group = &x2c_var_decode_groups[slot];
  unsigned selector = group.by_middle ? mid : btm & group.mask;
  return selector < 8 ? group.ids[selector] : _invalid_;
}

/* Rotating the top left one bit puts 0x0000-0x000F on the even slots and
   0x8000-0x800F on the odd slots below 32; every other top lands above. */
module inline unsigned _group_slot(unsigned top) =>
  ((top << 1) | (top >> 15)) & 0xFFFF;

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

module void *_address(Var value) =>
  (void *) (value.u64 & (_bitmask(48) - 0x7));

module inline unsigned long _bitmask(unsigned n) => (1ul << n) - 1;
