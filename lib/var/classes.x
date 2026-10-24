/*  classes.x -- custom class descriptors and addresses */

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
module typedef struct VarCell {
  VarDescriptor *descriptor;
  void *pointer;
  struct VarCell *next;
} VarCell;

static Map cells;

/* An overflow record keeps its descriptor in one aligned slot in front of
   the boxed copy, as Scope keeps its metadata in front of each payload. */
#define RECORD_PREFIX sizeof(max_align_t)

module VarDescriptor *_declared(Symbol tag) {
  if (declared == NULL) return NULL;
  Var found = declared[tag];
  return found is void ? NULL : found.pointer();
}

static unsigned _row_count(void) =>
  __atomic_load_n(&row_count, __ATOMIC_ACQUIRE);

module VarDescriptor *_row_descriptor(int id, Var value) {
  if (id == VAR_CELL_ROW) return ((VarCell *) _address(value)).descriptor;
  if (id == VAR_RECORD_ROW)
    return *(VarDescriptor **) ((char *) _address(value) - RECORD_PREFIX);
  return rows[id];
}

/* The four custom tops hold 32 rows, eight to a top in the bottom bits. A
   direct row is valid once assigned; an overflow row needs the address of
   its cell or record. */
module inline int _custom_top(unsigned top) =>
  top >= VAR_CUSTOM_TAG_TOP &&
  top < VAR_CUSTOM_TAG_TOP + VAR_CUSTOM_TAG_COUNT / 8;

module inline int _custom_id(unsigned top, unsigned bottom) =>
  (int) ((top - VAR_CUSTOM_TAG_TOP) * 8 + bottom);

module inline int _custom_valid(int id, Var value) =>
  id < VAR_DIRECT_ROWS ? id < (int) _row_count() : _address(value) != NULL;

/** Returns a boxed custom object's descriptor, or NULL for another value. */
VarDescriptor *x2c_var_custom_descriptor(Var value) {
  unsigned top = _top_bits(value);
  if (!_custom_top(top)) return NULL;
  int id = _custom_id(top, _bottom_bits(value));
  if (id < VAR_DIRECT_ROWS) return id < (int) _row_count() ? rows[id] : NULL;
  return _address(value) ? _row_descriptor(id, value) : NULL;
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
  if (row < 0) raise %(bad-target (operation "Var.box_record") (target $tag));
  if (row < VAR_DIRECT_ROWS)
    return _new_custom_pointer(row, xmemdup(record, size));
  char *copy = xmalloc(RECORD_PREFIX + size);
  *(VarDescriptor **) copy = descriptor;
  memcpy(copy + RECORD_PREFIX, record, size);
  return _new_custom_pointer(VAR_RECORD_ROW, copy + RECORD_PREFIX);
}

/* Returns custom `tag`'s row, assigning it on first box, or -1 when `tag`
   names no declared class. Sets `descriptor` for a declared class that has
   no direct row. */
module int _custom_row(Symbol tag, VarDescriptor *&descriptor) {
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

module VarCell *_cell(VarDescriptor *descriptor, void *pointer) {
  x2c_descriptor_thread_start_begin();
  defer x2c_descriptor_thread_start_end(0);
  Var key = { .p64 = pointer };
  VarCell *cell = NULL;
  auto(&class_scope) {
    if (cells == NULL) cells = {};
    Var head = cells[key];
    VarCell *first = head is void ? NULL : head.pointer();
    cell = first;
    while (cell && cell.descriptor != descriptor) cell = cell.next;
    if (!cell) {
      cell = xmalloc(sizeof(VarCell));
      *cell = (VarCell) { descriptor, pointer, first };
      cells[key] = (void *) cell;
    }
  }
  return cell;
}

module Var _new_custom_pointer(int id, void *ptr) {
  uintptr_t raw = (uintptr_t) ptr;
  Var v = { .u64 = raw & _bitmask(48) };
  v.u64 |= (unsigned long) (VAR_CUSTOM_TAG_TOP + id / 8) << 48;
  v.u64 |= id % 8;
  return v;
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
    raise %(bad-state (operation "Var.register_object_tag"));
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
  auto(&class_scope) {
    if (declared == NULL) declared = {};
    descriptor = xcalloc(1, sizeof(VarDescriptor));
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
