/*  func.x -- generic native function binding

    Copyright (c) 2026 Gary William Flake.

    `Func` owns the binding of one synchronous native call: a canonical
    signature, an adapter, and optional context bytes copied into the same
    `Scope` allocation. Arguments reach native code only through the checked
    value and reference readers that generated adapters call.
*/

#pragma once

#include "common.x"
#include "var/var.x"
#include "list/list.x"
#include "map/map.x"
#include "string/string.x"

Func Var.func(Var value);
protocol Var(Func);

/** Storage for either the value or reference member selected by `FuncArg`.
    Pointer-bearing `Var` storage and referenced objects belong to the caller.
*/
typedef union FuncArgData {
  Var value;
  const void *reference;
} FuncArgData;

/** Argument carrier borrowed for one synchronous `Func.apply` call.
    A null `reference_type` selects copied Var bits; `(splice)` selects a
    List whose elements enter a List rest tail, or a Map whose entries enter
    a Map rest tail. Otherwise, `reference`
    and its canonical source type are borrowed and must remain valid through
    the call. A reference target may be mutated by the native function.
*/
typedef struct FuncArg {
  FuncArgData data;
  List reference_type;
} FuncArg;

/** Uniform shape of a native `Func` adapter.
    A `Func` stores the callback pointer without retaining it and calls it
    synchronously with borrowed `fn` and `argv`; the callback code must outlive
    the `Func`. Compiler-generated adapters use the checked value and reference
    readers, call their native target, and box its result. A returned `void`
    remains no-value. Adapters receive no count. Fixed bindings check arity
    first. Rest bindings receive fixed arguments followed by one packed List.
*/
typedef Var (*FuncAdapter)(Func fn, const FuncArg *argv);

#include "error/error.x"
#include "exception.x"
#include "match/match.x"
#include "symbol.x"
#include "scope/scope.x"
#include "meta.x"

module {
  "errors.x",
}

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// binding layout

/* The Func's Scope owns one allocation containing the handle and optional
   max_align_t-aligned context bytes. `sig`, `params`, and `adapter` are stored
   without retaining their canonical Lists or callback code, so they must
   outlive the binding. A `rest` binding packs trailing value arguments into
   the final List (`rest` 1) or Map (`rest` 2) its adapter expects. A
   `shared` binding is the file-static
   handle that every conversion of one direct function reuses; it lives for the
   program, so `Func.move` leaves it in place. */
static struct Func {
  List sig, params, FuncAdapter adapter;
  unsigned nparams;
  int rest, shared;
  size_t context_size;
  unsigned char data[];
};

static size_t _context_offset(void) {
  size_t alignment = _Alignof(max_align_t);
  size_t remainder = sizeof(struct Func) % alignment;
  return remainder ? sizeof(struct Func) + alignment - remainder
                   : sizeof(struct Func);
}

static void *_context(Func f) => (unsigned char *) f + _context_offset();

// calls

/** Invokes a bound native function synchronously and returns its boxed result.
    `argv` is borrowed only for the call. Value bits are passed by value;
    reference arguments alias their caller-owned targets and may be mutated.
    A rest binding keeps its fixed arguments and interns one List containing
    trailing values in their original order. Explicit splices add their
    elements. A Map rest binding instead pairs the trailing values, each key
    followed by its value, into one fresh Map, and merges each spliced Map
    where it occurs; later entries win.
    Rest arguments must not be `void`, since Lists exclude void elements.

    Raises: `<bad-arg>` for a null binding or argument storage, `<bad-arity>`
    for the wrong argument count or a key without a value, `<void-op>`,
    `<bad-types>`, `<bad-enc>`, `<bad-target>`, `<no-convert>`, or
    `<conv-range>` while converting an argument, `<alloc-fail>` or
    `<size-limit>` while packing rest arguments, or any cause raised by the
    adapter or native target. A `void` adapter result remains no-value. Other
    results have the ownership of the value the adapter returned.
*/
Var Func.apply(Func f, unsigned argc, const FuncArg *argv) {
  if (!f || (argc && !argv)) $error.apply.args();
  if (!f.rest) {
    if (argc != f.nparams) {
      List sig = f.sig;
      unsigned expected = f.nparams;
      $error.apply.arity(sig, expected, argc);
    }
    return f.adapter(f, argv);
  }
  return _apply_rest(f, argc, argv);
}

/* Keep tail construction and its temporary array off the fixed-call path. */
static Var _apply_rest(Func f, unsigned argc, const FuncArg *argv) {
  unsigned fixed = f.nparams - 1;
  if (argc < fixed) $error.apply.arity(f.sig, fixed, argc);
  FuncArg packed[f.nparams];
  if (fixed) memcpy(packed, argv, fixed * sizeof(FuncArg));
  packed[fixed] = f.rest == 2
    ? FuncArg.value(_map_tail(f.sig, fixed, argc, argv))
    : FuncArg.value(_list_tail(f.sig, fixed, argc, argv));
  return f.adapter(f, packed);
}

static List _list_tail(
  List sig, unsigned fixed, unsigned argc, const FuncArg *argv) {
  List rest = NULL;
  for (unsigned i = argc; i > fixed; i--) {
    unsigned index = i - 1;
    if (argv[index].reference_type == %(splice)) {
      List items = argv[index].data.value;
      rest = items.append(rest);
    }
    else rest = cons(_tail_value(sig, argv, index), rest);
  }
  return rest;
}

static Map _map_tail(
  List sig, unsigned fixed, unsigned argc, const FuncArg *argv) {
  Map tail = Map.new();
  for (unsigned i = fixed; i < argc; i++) {
    if (argv[i].reference_type == %(splice)) {
      tail.merge(argv[i].data.value);
      continue;
    }
    if (i + 1 == argc) $error.apply.arity(sig, argc + 1, argc);
    Var key = _tail_value(sig, argv, i++);
    tail.set(key, _tail_value(sig, argv, i));
  }
  return tail;
}

/* A trailing value is passed by value and is not void. */
static Var _tail_value(List sig, const FuncArg *argv, unsigned index) {
  if (argv[index].reference_type) $error.arg.value(sig, index);
  Var value = argv[index].data.value;
  if (value is void) $error.arg.void(sig, index);
  return value;
}

/** Constructs a `Func` argument by copying one `Var` value.
    Pointer-bearing payload storage is not copied or retained and must outlive
    the call that consumes the argument.
*/
inline FuncArg FuncArg.value(Var value) => (FuncArg) { .data.value = value };

/** Marks an explicit List splice in a rest tail. The List is borrowed until
    the synchronous call completes; ordinary List values remain one element.
*/
FuncArg FuncArg.splice(List items) =>
  (FuncArg) { .data.value = items, .reference_type = %(splice) };

/** Marks an explicit Map splice in a Map rest tail. The Map is borrowed
    until the synchronous call completes.
*/
FuncArg FuncArg.splice_map(Map entries) =>
  (FuncArg) { .data.value = entries, .reference_type = %(splice) };

/** Prepares an explicit List splice only after the fixed parameters of a
    List rest binding.
    Raises `<bad-types>` when the splice occupies a fixed parameter or the
    binding has no List rest.
*/
FuncArg x2c_func_splice_argument(Func fn, unsigned index, List items) {
  _check_splice(fn, index, 1);
  return FuncArg.splice(items);
}

/** Prepares an explicit Map splice only after the fixed parameters of a
    Map rest binding.
    Raises `<bad-types>` when the splice occupies a fixed parameter or the
    binding has no Map rest.
*/
FuncArg x2c_func_map_splice_argument(Func fn, unsigned index, Map entries) {
  _check_splice(fn, index, 2);
  return FuncArg.splice_map(entries);
}

static void _check_splice(Func fn, unsigned index, int rest) {
  if (!fn) $error.apply.args();
  if (fn.rest != rest || index < fn.nparams - 1) {
    List sig = fn.sig;
    $error.arg.value(sig, index);
  }
}

/** Constructs a `Func` argument borrowing a typed lvalue address.
    The address and canonical `type` must remain valid through `Func.apply`;
    an optional reference may use a null address. This constructor performs
    no validation. Compiler-generated adapters use the checked reference
    reader before calling native code.
*/
inline FuncArg FuncArg.reference(const void *reference, List type) =>
  (FuncArg) { .data.reference = reference, .reference_type = type };

/** Applies `fn` to one argument passed by value.
    `value` travels as `FuncArg.value` carries it, so a callback with a
    reference parameter raises `<bad-types>`. Returns, owns, and raises as
    `Func.apply` does.
*/
inline Var Func.apply_value(Func fn, Var value) {
  FuncArg arguments[1] = { FuncArg.value(value) };
  return fn.apply(1, arguments);
}

/** Applies `fn` to two arguments passed by value, `left` then `right`.
    Each travels as `Func.apply_value` carries its argument. Returns, owns,
    and raises as `Func.apply` does.
*/
inline Var Func.apply_values(Func fn, Var left, Var right) {
  FuncArg arguments[2] = { FuncArg.value(left), FuncArg.value(right) };
  return fn.apply(2, arguments);
}

/* adapter arguments

   Dynamic-call lowering evaluates the Func expression once, queries every
   parameter before evaluating that source argument, initializes one FuncArg
   local at a time in source order, and only then calls Func.apply. The
   query-before-evaluation rule keeps output-only references unread; the
   locals keep argument order independent of C call evaluation. The helpers
   below consume that prepared array and do not retain it. */

/** Returns the borrowed pointee type for reference parameter `index`.
    A value or rest parameter returns NULL. Generated direct calls query it
    before evaluating the source argument, so an output-only lvalue is not
    read.

    Raises: `<bad-arg>` for a null `Func` or an index outside `argc`, or
    `<bad-arity>` when `argc` disagrees with a fixed signature.
*/
List x2c_func_reference_type(Func fn, unsigned argc, unsigned index) {
  if (!fn || index >= argc)
    $error.apply.index(index);
  unsigned fixed = fn.rest ? fn.nparams - 1 : fn.nparams;
  if (fn.rest && argc >= fixed && index >= fixed) return NULL;
  if (fn.rest ? argc < fixed : argc != fixed) {
    List sig = fn.sig;
    $error.apply.arity(sig, fixed, argc);
  }
  List parameter = _parameter(fn, index);
  return _is_reference(parameter) ? parameter.cdr() : NULL;
}

static List _parameter(Func fn, unsigned index) {
  if (!fn || index >= fn.nparams) return NULL;
  List params = fn.params;
  while (params && index--) params = params.cdr();
  return params && params.car() is <list> ? params.car() : NULL;
}

static int _is_reference(List parameter) =>
  parameter && (parameter.car() == <&> || parameter.car() == <opt-ref>);

/** Checks and converts value argument `i`, reporting its position.
    Generated adapters call this once per value parameter before unboxing, so a
    reference carrier or wrong tag is refused before reaching native code.
    `argv` must address the prepared argument array and `i` must be in bounds;
    compiler-generated adapters establish both facts.
    Raises: `<void-op>` for a `void` argument, `<bad-types>` when an object or
    `Symbol` argument does not carry `want` or the carrier holds a reference,
    and `<alloc-fail>`, `<bad-enc>`, `<bad-target>`, `<conv-range>`, or
    `<no-convert>` from a numeric conversion. The result has tag `want`.
    A detail names the argument's tag, since any tag may arrive here and an
    identity-bearing detail value terminates at the error floor before it
    reaches the handler that would report it.
*/
Var x2c_func_value_argument(
  Func fn, const FuncArg *argv, unsigned i, Symbol want) {
  List sig = fn ? fn.sig : NULL;
  if (argv[i].reference_type)
    $error.arg.value(sig, i);
  Var value = argv[i].data.value;
  if (want == <var>) return value;
  if (value is void) $error.arg.void(sig, i);
  X2CVarNumericInfo info;
  if (Var.numeric_info(want, info)) {
    if (!info.floating && info.rank <= 4 &&
        value.encoding_valid() && value.is_integer())
      return value.convert(want);
    Var converted = void;
    try {
      converted = value.convert(want);
    }
    catch %((!or ?code bad-enc void-op bad-target conv-range no-convert)
            *cause): {
      List lower = cons(code, cause);
      $error.arg.convert(code, sig, i, want, lower);
    }
    return converted;
  }
  /* Object parameters require their declared tag, but nil is a legal List. */
  if (value is not want && !(want == <list> && value.is_null()))
    $error.arg.type(sig, i, value.tag(), want);
  return value;
}

/** Returns the address value argument `i` carries. Generated adapters use it
    for a pointer parameter with no `Var` tag of its own, such as
    `const char *` or `struct timespec *`, and for a record passed by value,
    whose bytes the adapter copies. Any pointer, reference, or `String`
    argument is accepted, as C converts it to the parameter's pointer type.
    Raises: `<bad-types>` for any other argument.
*/
void *x2c_func_pointer_argument(Func fn, const FuncArg *argv, unsigned i) {
  Var value = argv[i].data.value;
  Symbol kind = value.kind();
  if (argv[i].reference_type ||
      (kind != <pointer> && kind != <reference> && value is not <string>)) {
    List sig = fn ? fn.sig : NULL;
    $error.arg.pointer(sig, i, value.tag());
  }
  return value.pointer();
}

/** Rejects a value argument whose source type has no `Var` representation.
    Generated calls use this branch instead of compiling an impossible
    conversion. Raises: `<bad-types>`.
*/
FuncArg x2c_func_unrepresentable_argument(Func fn, unsigned i, List source) {
  List sig = fn ? fn.sig : NULL;
  $error.arg.unboxed(sig, i, source);
}

/** Boxes a record result as a `<p48>` to a copy of its `size` bytes in the
    active `Scope`.
*/
Var x2c_func_record_result(const void *bytes, size_t size) =>
  Var.new(<p48>, xmemdup(bytes, size));

// reference arguments

/** Checks a reference argument whose stored pointee matches `want` exactly.
    Raises: `<bad-types>` on the same mismatches as the shared checker.
*/
void *x2c_func_reference_argument(
  Func fn, const FuncArg *argv, unsigned i, List want) =>
  _reference_argument(fn, argv, i, want, want);

/** Checks a generated adapter's declared pointee against the stored signature
    and its resolved `want` against the source address before casting.
    Raises: `<bad-types>` on either mismatch.
*/
void *x2c_func_declared_reference_argument(
  Func fn, const FuncArg *argv, unsigned i, List declared_target, List want) =>
  _reference_argument(fn, argv, i, declared_target, want);

/* Returns reference argument `i` after checking its declared source type.
    The adapter supplies the pointee type it will cast to.
    `argv` must address the prepared argument array and `i` must be in bounds;
    generated adapters establish both facts.
    Raises: `<bad-types>` when the carrier is a value, its address is null for
    a required reference, the `Func` signature and adapter disagree, its type
    differs, or conversion would discard a qualifier. It does not return on
    failure.
*/
static void *_reference_argument(
  Func fn, const FuncArg *argv, unsigned i, List declared_target, List want) {
  List declared = _parameter(fn, i), source = argv[i].reference_type;
  int signature_reference = _is_reference(declared);
  List target = signature_reference ? declared.cdr() : NULL;
  if (!source ||
      (!argv[i].data.reference && declared.car() != <opt-ref>) ||
      !signature_reference || !want ||
      target != declared_target ||
      (!_reference_type_accepts(want, source) &&
       !_reference_type_accepts(declared_target, source))) {
    List sig = fn ? fn.sig : NULL;
    $error.arg.ref(sig, i, source, want);
  }
  return (void *) argv[i].data.reference;
}

/* A reference aliases the source object itself, so only that object's leading
   qualifiers may be strengthened. The remaining declarator must be exact:
   accepting int * as const int * would expose int ** as const int **. */
static int _reference_type_accepts(List target, List source) {
  unsigned target_qualifiers = _type_qualifiers(target);
  unsigned source_qualifiers = _type_qualifiers(source);
  return !(source_qualifiers & ~target_qualifiers) &&
         target == source;
}

static unsigned _type_qualifiers(List &cursor) {
  unsigned qualifiers = 0;
  while (cursor && cursor.car() is <symbol>) {
    Symbol head = cursor.car();
    switch (head) {
      case <const>:    qualifiers |= 1; break;
      case <volatile>: qualifiers |= 2; break;
      case <restrict>: qualifiers |= 4; break;
      default: return qualifiers;
    }
    cursor = cursor.cdr();
  }
  return qualifiers;
}

// construction

/** Builds a native-function binding in the current `Scope`.
    A final `(.... "List")` or `(.... "Map")` signature parameter, the Type
    of a `List @name` or `Map @name` parameter, selects rest calling
    semantics.
    A direct function expression is compiler-adapted; an expression already
    typed `FuncAdapter` is stored as supplied. The canonical `signature` and
    adapter code are borrowed for the `Func` lifetime. Only the signature's
    outer shape is checked here, so a hand-written adapter must agree with its
    parameter count and types.
    Raises: `<bad-sig>` for a null adapter or a malformed signature, and
    `<alloc-fail>` when binding storage cannot be allocated.
*/
Func Func.new(FuncAdapter adapter, List signature) =>
  _new(adapter, signature, 0, NULL, 0);

/** Builds a native binding with fixed parameters and a List rest tail.
    The signature ends in `List` or `(.... "List")`. The adapter receives
    fixed arguments followed by a List containing the remaining values in
    order.
    A signature with only one List parameter retains the zero-prefix behavior.
    The canonical signature and adapter code are borrowed for the Func
    lifetime. The result belongs to the current Scope.
    Raises: `<bad-sig>` for a null adapter, malformed signature, or a final
    parameter other than List or `(.... "List")`, and `<alloc-fail>` for
    storage.
*/
Func Func.new_rest(FuncAdapter adapter, List signature) =>
  _new(adapter, signature, 1, NULL, 0);

/** Builds a binding with copied context in the current `Scope`.
    A final `(.... "List")` or `(.... "Map")` signature parameter, the Type
    of a `List @name` or `Map @name` parameter, selects rest calling
    semantics.
    The max_align_t-aligned bytes share the `Func` allocation. The byte copy is
    shallow: changing the source bytes does not change the binding, while any
    pointers inside them keep their original targets and lifetimes. A zero
    size may use NULL storage. The canonical `signature` and adapter code are
    borrowed for the `Func` lifetime.
    Raises: `<bad-arg>` when a nonzero size has no source, `<size-limit>` when
    the allocation size overflows, `<bad-sig>` for a null adapter or malformed
    signature, or `<alloc-fail>` when storage cannot be allocated. None return.
*/
Func Func.new_context(
  FuncAdapter adapter, List signature,
  const void *context, size_t context_size) =>
    _new(adapter, signature, 0, context, context_size);

/** Builds the shared handle for a direct function or noncapturing lambda.
    The compiler stores the result in a file-static `Func` that every
    conversion of that function reuses, so the binding lives for the program
    and `Func.move` never transfers it.
    Raises: the causes of `Func.new`.
*/
Func x2c_func_shared(FuncAdapter adapter, List signature) {
  Func fn = _new(adapter, signature, 0, NULL, 0);
  fn.shared = 1;
  return fn;
}

/* Constructors accept canonical `((func (ptype ...)) rtype ...)` Lists. The
   pattern checks only that outer shape; compiler-generated adapters
   interpret the parameters and result. */
static Func _new(
  FuncAdapter adapter, List signature, int rest,
  const void *context, size_t context_size) {
  if (!adapter) $error.bind.sig(signature);
  List params = NULL;
  if (signature ~= %((func (!is ?captured type list)) ? *))
    params = captured;
  if (!params) $error.bind.sig(signature);
  if (context_size && !context)
    $error.context.source();
  size_t context_offset = _context_offset();
  if (context_size > SIZE_MAX - context_offset)
    $error.context.size(context_size);
  Var last = params.last();
  if (last == %(.... "List")) rest = 1;
  else if (last == %(.... "Map")) rest = 2;
  else if (rest && last != %("List"))
    $error.bind.sig(signature);
  int n = params.len();
  int void_params = n == 1 && params.car() is <list> &&
                    params.car() == %(void);
  Func fn = xcalloc(1, context_offset + context_size);
  fn.sig = signature;
  fn.params = void_params ? NULL : params;
  fn.adapter = adapter;
  fn.rest = rest;
  fn.context_size = context_size;
  fn.nparams = void_params ? 0 : n;
  if (context_size) memcpy(_context(fn), context, context_size);
  return fn;
}

// access and boxing

/** Returns a native binding's borrowed canonical signature.
    The result has the `((func (PARAMETERS...)) RESULT...)` shape supplied to
    the constructor and remains valid for the binding's lifetime.
*/
List Func.signature(Func function) {
  if (!function) $error.signature.null();
  return function.sig;
}

/** Returns borrowed read-only access to a `Func`'s copied context.
    The pointer remains valid only for the `Func`'s `Scope` lifetime and is
    NULL when the binding has no context.
    Raises: `<bad-arg>` for a null binding. It does not return on failure.
*/
const void *Func.context(Func function) {
  if (!function) $error.context.null();
  return function.context_size ? _context(function) : NULL;
}

/** Transfers `function`'s storage to the `Scope` held by `slot`.
    The shared handle of a direct function or noncapturing lambda lives for
    the program and stays where it is, so a caller may hand any `Func` to an
    operation that takes ownership. A NULL `function` does nothing.
    Raises: the causes of `Scope.move`, which leave ownership unchanged.
*/
void Func.move(Func function, Scope *slot) {
  if (function && !function.shared) Scope.move(function, slot);
}

/** Boxes `function` without copying or retaining the `Func`.
    The returned `Var` carries the same pointer and shares its `Scope`
    lifetime.
*/
Var Func.var(Func function) => Var.new(<func>, function);

/** Returns the borrowed native callable carried by `v`.
    Raises: `<bad-types>` when the value is not a `Func`.
*/
Func Var.func(Var v) {
  if (v is not <func>) $error.box.type(v.tag());
  return v.pointer();
}
