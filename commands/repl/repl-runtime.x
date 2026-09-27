/* Interpreter storage and native crossings owned by the REPL command. */
#pragma once
#include "lisp.x"

macro Expression $repl._values() =>
  $(x2c.literal.string (_x2c.embed.text "../../etc/lisp-values.xlisp"));
macro Expression $repl._runtime() =>
  $(x2c.literal.string (_x2c.embed.text "repl-runtime.xlisp"));

/* Raw evaluation slots transport terminal values without storing them in
   ordinary collections. Bindings use separately allocated cells because a
   Map deliberately excludes void from its value domain. */
/** Returns the `void` sentinel to the evaluator. */
Var lisp_void(void) => void;

static Var _cell(Scope *owner, Var value) {
  Var *slot = Scope.malloc_in(owner, sizeof(Var));
  *slot = value;
  return Var.new(<var*>, slot);
}

/** Allocates one evaluator-owned raw `Var` slot initialized to `value`. */
Var lisp_cell(Var value) => _cell(Lisp.active().storage(), value);
/** Retags an evaluator value at a declared pointer or Symbol crossing. */
Var lisp_address(Var cell, Symbol tag) {
  if (tag == <symbol>) return (Symbol) cell.ulong();
  return Var.new(tag, cell.pointer());
}
/** Returns the raw value currently held in an evaluator cell. */
Var lisp_load(Var cell) => *((Var *) cell.pointer());
/** Stores `value` in an evaluator cell and returns it. */
Var lisp_store(Var cell, Var value) {
  *((Var *) cell.pointer()) = value;
  return value;
}

/* Lowered source keeps C objects in native bytes. The compiler supplies
   every size, offset, and layout from `ReplLower.type_layout`, so these
   operations only move bytes. The per-access operations take their offset
   as a `Var`: a `long` parameter would convert and box each offset, which
   adds about 10% to a field access. Automatic storage belongs to the frame
   of the marked source function executing it, or to the session outside
   one. */
static Scope *_lowered_owner(void) =>
  Lisp.active().automatic_storage();

/** Allocates `size` zeroed bytes of lowered automatic storage. */
Var lisp_bytes(long size) =>
  Var.new(<p48>, Scope.calloc_in(_lowered_owner(), 1, (size_t) size));

/** Returns `base` advanced by `offset` bytes, tagged as `tag`. */
Var lisp_at(Var base, Var offset, Symbol tag) =>
  Var.new(tag, (char *) base.pointer() + offset.long_long());

/** Zeroes `size` bytes at `destination` and returns it. */
Var lisp_zero(Var destination, Var size) {
  memset(destination.pointer(), 0, (size_t) size.long_long());
  return destination;
}

/** Copies `size` bytes from `source` to `destination`; returns the latter. */
Var lisp_copy(Var destination, Var source, long size) {
  memmove(destination.pointer(), source.pointer(), (size_t) size);
  return destination;
}

/** Copies a returned record into its caller's automatic storage before the
    returning frame ends. */
Var lisp_record_result(Var source, long size) {
  void *copy = Scope.memdup_in(
    Lisp.active().result_storage(),
    source.pointer(), (size_t) size);
  return Var.new(<p48>, copy);
}

/** Copies a record, or a wide scalar's box, into storage the session owns,
    for persistent state and captures. `size` is the record's size. */
Var lisp_session_copy(Var source, long size) {
  if (source.is_wide())
    return Var.clone_wide(source).move_wide_to(Lisp.active().storage());
  void *copy = Scope.memdup_in(
    Lisp.active().storage(), source.pointer(), (size_t) size);
  return Var.new(<p48>, copy);
}

/* A scalar layout's TAG can differ from its bytes' row: a bool's byte reads
   as the int C promotes it to, and a Symbol's unsigned-long bytes hold its
   code. A numeric value converts, and a Symbol's code is its bits. */
static Var _lisp_scalar_as(Var value, Symbol tag) {
  X2CVarNumericInfo info;
  if (value.tag() == tag) return value;
  if (!Var.numeric_info(tag, info)) return Var.new(tag, value.ulong());
  if (!Var.numeric_info(value.tag(), info))
    return Var.integer_box(tag, (unsigned long) value.integer());
  return value.convert(tag);
}

/** Boxes a source value at the compiler-selected native Var tag. */
Var lisp_box(Symbol tag, Var value) {
  if (tag == value.tag()) return value;
  X2CVarNumericInfo info;
  if (Var.numeric_info(tag, info)) return value.convert(tag);
  return lisp_address(value, tag);
}

/** Reads the object of compiler layout `layout` at `offset` bytes past
    `pointer`. A record reads as its own address, which is how lowered source
    carries record values. */
Var lisp_peek(Var pointer, Var offset, List layout) {
  void *at = (char *) pointer.pointer() + offset.long_long();
  match (layout) {
    case %(record *): return Var.new(<p48>, at);
    case %(var *): return *(Var *) at;
    case %(pointer ? ? ? ?tag): return Var.new(tag, *(void **) at);
    case %(scalar ? ? ? ?exact ?tag): {
      Var value = native_scalar_access(exact).load(at, Scope.top());
      return _lisp_scalar_as(value, tag);
    }
  }
  return void;
}

/** Writes `value`, already converted to the layout's type, at `offset`
    bytes past `pointer`. */
Var lisp_poke(Var pointer, Var offset, List layout, Var value) {
  void *at = (char *) pointer.pointer() + offset.long_long();
  match (layout) {
    case %(record ? ?size *): memmove(at, value.pointer(), size.long_long());
    case %(var *): *(Var *) at = value;
    case %(pointer *): *(void **) at = value.pointer();
    case %(scalar ? ? ? ?exact *): {
      NativeScalarAccess scalar = native_scalar_access(exact);
      scalar.store(at, _lisp_scalar_as(value, scalar.tag));
    }
  }
  return value;
}

/** Builds a local C array in live native storage, shared by indexing and
    references to its elements. Initializer values already have element
    type. */
Var lisp_array(List layout, List values) {
  (long size) = layout.cddr();
  long offset = 0;
  Var storage = lisp_bytes(size * values.len());
  foreach (Var value, values) {
    lisp_poke(storage, offset, layout, value);
    offset += size;
  }
  return storage;
}

Var lisp_unwind(Var body, Var cleanup, List arguments) {
  Lisp lisp = Lisp.active();
  defer lisp.apply(cleanup, arguments);
  return lisp.apply(body, arguments);
}

typedef struct ReplCallbackContext {
  Lisp lisp;
  Var callable;
} ReplCallbackContext;

/* A source Func keeps its canonical signature while its adapter executes in
   the owning Lisp session. The lowered adapter reads the borrowed carriers
   with the ordinary native Func argument readers. */
static Var _lisp_func_adapter(Func function, const FuncArg *arguments) {
  ReplCallbackContext *context = (void *) function.context();
  if (!Lisp.active() || Lisp.active() != context.lisp)
    raise %(bad-state (operation "Lisp callback") (why "wrong session"));
  Var argv = Var.new(<p48>, arguments);
  return context.lisp.apply(context.callable, %($function $argv));
}

/** Constructs a signature-bearing Func for one lowered source callable. */
Func lisp_func_new(Var adapter, List signature) {
  ReplCallbackContext context = { Lisp.active(), adapter };
  Func function = Func.new_context(
    _lisp_func_adapter, signature, &context, sizeof context);
  Scope.move(function, Lisp.active().storage());
  return function;
}

/** Allocates the borrowed carriers for one lowered dynamic call. */
void *lisp_func_arguments(unsigned count) =>
  Scope.calloc_in(_lowered_owner(), count + 1, sizeof(FuncArg));

/** Prepares one value without excluding the terminal void value. */
void *lisp_func_value(FuncArg *argv, unsigned index, Var value) {
  argv[index] = FuncArg.value(value);
  return argv;
}

/** Prepares an address without loading the caller's object. A non-lvalue
    supplies zero, which the ordinary reference reader rejects. */
void *lisp_func_reference(
  FuncArg *argv, unsigned index, Var address, List source) {
  void *pointer = address.is_integer() && !address.integer()
                ? NULL : address.pointer();
  argv[index] = FuncArg.reference(pointer, source);
  return argv;
}

/** Uses the native rejection for an unrepresentable value argument. */
Var lisp_func_invalid(Func fn, unsigned index, List source) {
  (void) x2c_func_unrepresentable_argument(fn, index, source);
  return void;
}

void repl_runtime_initialize(Lisp lisp) {
  $lisp.bind(lisp, "repl.native.lisp_func_value", lisp_func_value);
  $lisp.bind(lisp, "repl.native.lisp_func_reference", lisp_func_reference);
  $lisp.bind(lisp, "repl.native.lisp_void", lisp_void);
  $lisp.bind(lisp, "repl.native.lisp_cell", lisp_cell);
  $lisp.bind(lisp, "repl.native.lisp_address", lisp_address);
  $lisp.bind(lisp, "repl.native.lisp_load", lisp_load);
  $lisp.bind(lisp, "repl.native.lisp_store", lisp_store);
  $lisp.bind(lisp, "repl.native.lisp_bytes", lisp_bytes);
  $lisp.bind(lisp, "repl.native.lisp_at", lisp_at);
  $lisp.bind(lisp, "repl.native.lisp_zero", lisp_zero);
  $lisp.bind(lisp, "repl.native.lisp_copy", lisp_copy);
  $lisp.bind(lisp, "repl.native.lisp_record_result", lisp_record_result);
  $lisp.bind(lisp, "repl.native.lisp_session_copy", lisp_session_copy);
  $lisp.bind(lisp, "repl.native.lisp_box", lisp_box);
  $lisp.bind(lisp, "repl.native.lisp_peek", lisp_peek);
  $lisp.bind(lisp, "repl.native.lisp_poke", lisp_poke);
  $lisp.bind(lisp, "repl.native.lisp_array", lisp_array);
  $lisp.bind(lisp, "repl.native.lisp_unwind", lisp_unwind);
  $lisp.bind(lisp, "repl.native.lisp_func_new", lisp_func_new);
  $lisp.bind(lisp, "repl.native.lisp_func_invalid", lisp_func_invalid);
  $lisp.bind(lisp, "repl.native.lisp_source_function", lisp_source_function);
  $lisp.bind(lisp, "repl.native.lisp_func_arguments", lisp_func_arguments);
  $lisp.bind(lisp, "repl.native.x2c_func_reference_type",
    x2c_func_reference_type);
  $lisp.bind(lisp, "repl.native.x2c_func_reference_argument",
    x2c_func_reference_argument);
  $lisp.bind(lisp, "repl.native.x2c_func_declared_reference_argument",
    x2c_func_declared_reference_argument);
  $lisp.bind(lisp, "repl.native.x2c_func_value_argument",
    x2c_func_value_argument);
  $lisp.bind(lisp, "repl.native.x2c_func_pointer_argument",
    x2c_func_pointer_argument);
  lisp.eval_string($repl._values());
  lisp.eval_string($repl._runtime());
  lisp.eval_string("(def C._globals (Map.new))");
}
