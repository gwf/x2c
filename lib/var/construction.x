/*  construction.x -- tag-directed Var construction */

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
    cannot be represented or a pointer does not satisfy its tag's alignment.
*/
Var Var.new(Symbol tag, ...) {
  va_list ap, TagId id = _tag2id(tag);
  VarDescriptor *descriptor = NULL;
  int row = id == _invalid_ ? _custom_row(tag, descriptor) : -1;
  if (id == _invalid_ && row < 0)
    raise %(bad-target (operation "Var.new") (target $tag));
  va_start(ap, tag);
  if (row >= 0) {
    void *pointer = va_arg(ap, void *);
    va_end(ap);
    _require_aligned(tag, pointer, 0x7);
    if (row < VAR_DIRECT_ROWS) return _new_custom_pointer(row, pointer);
    return _new_custom_pointer(VAR_CELL_ROW, _cell(descriptor, pointer));
  }
  Var v = _new_builtin(id, tag, ap);
  va_end(ap);
  return v;
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
      if (!str.try_long(value) || value < INT_MIN || value > INT_MAX)
        return void;
      return (int) value;
    }
    case <float>: case <double>: {
      double value;
      if (!str.try_double(value)) return void;
      return value;
    }
    case <string>:    return str.parse();
    case <symbol>:    return Symbol.parse(str);
    case <char>:      return str.parse_char();
    default:          return void;
  }
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
  raise %(invariant (operation "Var.new") (target $tag));
}

/* Pointer families store only the low 48 address bits and reclaim the
   alignment bits implied by their C type for the row subtype. Their decode
   group's mask covers exactly those bits, never more than three, so an
   8-byte-aligned address skips the lookup. Array and Map are the only rows
   whose null payload is invalid. */
static Var _new_pointer(TagId id, void *ptr) {
  unsigned long top = x2c_var_taginfo[id].top;
  if ((id == _array_ || id == _map_) && !ptr) {
    Symbol tag = x2c_var_taginfo[id].tag;
    raise %(bad-arg (operation "Var.new") (target $tag));
  }
  if ((uintptr_t) ptr & 0x7) {
    unsigned mask = x2c_var_decode_groups[_group_slot(top)].mask;
    _require_aligned(x2c_var_taginfo[id].tag, ptr, mask);
  }
  Var v = { .p64 = ptr };
  v.u64 |= top << 48;
  v.u64 |= x2c_var_taginfo[id].bottom;
  return v;
}

/* An address shares its low bits with the row selector, so the bits under
   `mask` must be clear. Raising from `_misaligned` keeps this test small
   enough for clang to inline at both callers. */
static inline void _require_aligned(Symbol tag, void *address, unsigned mask) {
  if ((uintptr_t) address & mask) _misaligned(tag);
}

static void _misaligned(Symbol tag) {
  raise %(bad-enc (operation "Var.new") (target $tag));
}

/* `<f32>` arrives promoted to `double`. */
static Var _floating_arg(TagId id, Symbol tag, va_list ap) {
  if (tag == <ldouble>) return Var.box_long_double(va_arg(ap, long double));
  return _new_floating(id, va_arg(ap, double));
}

/* An `<f32>` fills the low half under its row's prefix. An `<f64>` is the
   double shifted by (1 << 52); NaN, the infinities, and -DBL_MAX have their
   own encodings. Reading the prefixes from the table keeps each case a
   branch, where `Var.box_f32` and `Var.box_f64` let clang compute both
   encodings and select one. */
static Var _new_floating(TagId id, double d) {
  if (id == _f32_) {
    float f = (float) d;
    unsigned u;
    memcpy(&u, &f, sizeof u);
    return (Var) { .u64 = u | _prefix(_f32_) };
  }
  if (d != d) return (Var) { .u64 = _prefix(_nan_) };
  if (d > 0 && d == 1.0 / 0.0) return (Var) { .u64 = _prefix(_posinf_) };
  if (d < 0 && d == -1.0 / 0.0) return (Var) { .u64 = _prefix(_neginf_) };
  unsigned long u;
  memcpy(&u, &d, sizeof u);
  if (u == VAR_F64_NEG_MAX_RAW) return (Var) { .u64 = VAR_F64_NEG_MAX_ESCAPE };
  return (Var) { .u64 = u + VAR_F64_SHIFT };
}

/* The top and middle fields of an immediate row. */
static unsigned long _prefix(TagId id) =>
  x2c_var_taginfo[id].top << 48 | x2c_var_taginfo[id].middle << 32;

/* Tags up to 32 bits arrive promoted to `int` or `unsigned int`. */
static Var _integer_arg(TagId id, Symbol tag, va_list ap) {
  switch (tag) {
    case <u8>: case <i8>: case <u16>: case <i16>: case <i32>:
      return _new_integer(id, va_arg(ap, int));
    case <u32>:    return _new_integer(id, (long) va_arg(ap, unsigned int));
    case <u48>:    return _new_integer(id, (long) va_arg(ap, unsigned long));
    case <i48>:    return _new_integer(id, va_arg(ap, long));
    case <long>:   return Var.box_long(va_arg(ap, long));
    case <ulong>:  return Var.box_ulong(va_arg(ap, unsigned long));
    case <llong>:  return Var.box_long_long(va_arg(ap, long long));
    case <ullong>: return Var.box_ulong_long(va_arg(ap, unsigned long long));
  }
  raise %(invariant (operation "Var.new") (target $tag));
}

/* An immediate integer keeps its tag's width of payload bits. The 48-bit
   rows carry no middle field. */
static Var _new_integer(TagId id, long value) {
  unsigned bits = _integer_width(id);
  if (!_integer_fits(id, value, bits)) {
    Symbol target = x2c_var_taginfo[id].tag;
    raise %(conv-range (operation "Var.new") (target $target));
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
    default: raise %(invariant (operation "Var.new"));
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
  if (u >= (1ul << 51))
    raise %(conv-range (operation "Var.new") (target symbol));
  return (Var) { .u64 = u + VAR_SYMBOL_OFFSET };
}
