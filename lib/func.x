/*  func.x -- generic native function binding

    Copyright (c) 2026 Gary William Flake.

    `Func` binds a synchronous native call. It stores a typed signature and
    adapter, checks boxed value and typed-reference arguments, and boxes the
    adapter result. A bound context is copied into the same `Scope` allocation
    as the `Func`.
*/

#pragma once

#include "common.x"
#include "var.x"
#include "list.x"
#include "string.x"

/** Storage for either the value or reference member selected by `FuncArg`.
    Pointer-bearing `Var` storage and referenced objects belong to the caller.
*/
typedef union FuncArgData {
  Var value;
  const void *reference;
} FuncArgData;

/** Argument carrier borrowed for one synchronous `Func.apply` call.
    A null `reference_type` selects the copied `Var` bits; otherwise
    `reference`
    and the canonical source type are borrowed and must remain valid through
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
    is rejected. Adapters receive no count. Fixed bindings check arity first,
    and rest bindings receive one packed `List` argument.
*/
typedef Var (*FuncAdapter)(Func fn, const FuncArg *argv);

#pragma private

#include "varconvert.x"
#include "error.x"
#include "exception.x"
#include "match.x"
#include "symbol.x"
#include "scope.x"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* The Func's Scope owns one allocation containing the handle and optional
   max_align_t-aligned context bytes. `sig`, `params`, and `adapter` are stored
   without retaining their canonical Lists or callback code, so they must
   outlive the binding. A `rest` binding conses value arguments into the one
   List its adapter expects. */
struct Func {
  List sig, params, FuncAdapter adapter;
  unsigned nparams;
  int rest;
  size_t context_size;
  unsigned char data[];
};

/** Constructs a `Func` argument by copying one `Var` value.
    Pointer-bearing payload storage is not copied or retained and must outlive
    the call that consumes the argument.
*/
inline FuncArg FuncArg.value(Var value) {
  FuncArg argument = { 0 };
  argument.data.value = value;
  return argument;
}

/** Constructs a `Func` argument borrowing a typed lvalue address.
    The address and canonical `type` must remain valid through `Func.apply`;
    this constructor performs no validation. Compiler-generated adapters use
    the checked reference reader before calling native code.
*/
inline FuncArg FuncArg.reference(const void *reference, List type) {
  FuncArg argument = { 0 };
  argument.data.reference = reference;
  argument.reference_type = type;
  return argument;
}

static List _parameters(Func function) => function ? function.params : NULL;

static List _parameter(Func function, unsigned index) {
  if (!function || index >= function.nparams) return NULL;
  List params = _parameters(function);
  while (params && index--) params = params.cdr();
  return params && params.car() is <list> ? params.car().list() : NULL;
}

/* Dynamic-call lowering evaluates the Func expression once, queries every
   parameter before evaluating that source argument, initializes one FuncArg
   local at a time in source order, and only then calls Func.apply. The
   query-before-evaluation rule keeps output-only references unread; the locals
   keep argument order independent of C call evaluation. The helpers below
   consume that prepared array and do not retain it. */
/** Returns the borrowed pointee type for reference parameter `index`.
    A value or rest parameter returns NULL. Generated direct calls query it
    before evaluating the source argument, so an output-only lvalue is not
    read.

    Raises: `<bad-arg>` for a null `Func` or an index outside `argc`, or
    `<bad-arity>` when `argc` disagrees with a fixed signature. */
List x2c_func_reference_type(
  Func function, unsigned argc, unsigned index) {
  if (!function || index >= argc)
    raise %(bad-arg (operation "Func.apply") (index $index));
  if (function.rest) return NULL;
  if (argc != function.nparams) {
    List sig = function.sig;
    unsigned expected = function.nparams;
    raise %(bad-arity (sig $sig) (expected $expected) (actual $argc));
  }
  List parameter = _parameter(function, index);
  return parameter && parameter.car() == <&> ? parameter.cdr() : NULL;
}

static unsigned _type_qualifiers(List *cursor) {
  unsigned qualifiers = 0;
  while (*cursor && (*cursor).car() is <symbol>) {
    Symbol head = (*cursor).car();
    switch (head) {
      case <const>:    qualifiers |= 1; break;
      case <volatile>: qualifiers |= 2; break;
      case <restrict>: qualifiers |= 4; break;
      default: return qualifiers;
    }
    *cursor = (*cursor).cdr();
  }
  return qualifiers;
}

/* A reference aliases the source object itself, so only that object's leading
   qualifiers may be strengthened. The remaining declarator must be exact:
   accepting int * as const int * would expose int ** as const int **. */
static int _reference_type_accepts(List target, List source) {
  unsigned target_qualifiers = _type_qualifiers(&target);
  unsigned source_qualifiers = _type_qualifiers(&source);
  return !(source_qualifiers & ~target_qualifiers) &&
         List.equal(target, source);
}

/** Checks and converts value argument `i`, reporting its position.
    Generated adapters call this once per value parameter before unboxing, so a
    reference carrier or wrong tag is refused before reaching native code.
    `argv` must address the prepared argument array and `i` must be in bounds;
    compiler-generated adapters establish both facts.
    Raises: `<void-op>` for a `void` argument, `<bad-types>` when an object or
    `Symbol` argument does not carry `want` or the carrier holds
    a reference, and
    `<alloc-fail>`, `<bad-enc>`, `<bad-target>`, `<conv-range>`, or
    `<no-convert>` from a numeric conversion. The result has tag `want`.
*/
Var x2c_func_value_argument(
  Func fn, const FuncArg *argv, unsigned i, Symbol want) {
  List sig = fn ? fn.sig : NULL;
  if (argv[i].reference_type)
    raise %(bad-types (sig $sig) (index $i)
                      (want value));
  Var value = argv[i].data.value;
  if (value is void) raise %(void-op (sig $sig) (index $i));
  if (want == <var>) return value;
  X2CVarNumericInfo info;
  if (Var.numeric_info(want, &info)) {
    Var converted = void;
    try {
      converted = value.convert(want);
    }
    catch %(bad-enc *cause): {
      Symbol lower_code = <bad-enc>, List lower = cons(lower_code, cause);
      raise %(bad-enc (sig $sig) (index $i) (value $value)
                       (want $want) (cause $lower));
    }
    catch %(void-op *cause): {
      Symbol lower_code = <void-op>, List lower = cons(lower_code, cause);
      raise %(void-op (sig $sig) (index $i) (value $value)
                       (want $want) (cause $lower));
    }
    catch %(bad-target *cause): {
      Symbol lower_code = <bad-target>, List lower = cons(lower_code, cause);
      raise %(bad-target (sig $sig) (index $i) (value $value)
                          (want $want) (cause $lower));
    }
    catch %(conv-range *cause): {
      Symbol lower_code = <conv-range>, List lower = cons(lower_code, cause);
      raise %(conv-range (sig $sig) (index $i) (value $value)
                          (want $want) (cause $lower));
    }
    catch %(no-convert *cause): {
      Symbol lower_code = <no-convert>, List lower = cons(lower_code, cause);
      raise %(no-convert (sig $sig) (index $i) (value $value)
                          (want $want) (cause $lower));
    }
    return converted;
  }
  /* Object parameters require their declared tag, but nil is a legal List. */
  if (value is not want && !(want == <list> && value.is_null()))
    raise %(bad-types (sig $sig) (index $i) (value $value)
                       (want $want));
  return value;
}

/** Returns reference argument `i` after checking its declared source type.
    The generated adapter supplies the target pointee type it will cast to.
    `argv` must address the prepared argument array and `i` must be in bounds;
    compiler-generated adapters establish both facts.
    Raises: `<bad-types>` when the carrier is a value, its address is null, the
    `Func` signature and adapter disagree, its type differs, or conversion
    would
    discard a qualifier. It does not return on failure.
*/
void *x2c_func_reference_argument(
  Func fn, const FuncArg *argv, unsigned i, List want) {
  List declared = _parameter(fn, i), source = argv[i].reference_type;
  int signature_reference = declared && declared.car() == <&>;
  List target = signature_reference ? declared.cdr() : NULL;
  if (!source || !argv[i].data.reference || !signature_reference || !want ||
      !List.equal(target, want) ||
      !_reference_type_accepts(want, source)) {
    List sig = fn ? fn.sig : NULL;
    raise %(bad-types (sig $sig) (index $i)
                      (source $source) (want $want));
  }
  return (void *) argv[i].data.reference;
}

/** Rejects a value argument whose source type has no `Var` representation.
    Generated calls use this branch instead of compiling an impossible
    conversion. Raises: `<bad-types>`.
*/
FuncArg x2c_func_unrepresentable_argument(
  Func fn, unsigned i, List source) {
  List sig = fn ? fn.sig : NULL;
  raise %(bad-types (sig $sig) (index $i) (source $source) (want value));
  return FuncArg.value(void);
}

static size_t _context_offset(void) {
  size_t alignment = _Alignof(max_align_t);
  size_t remainder = sizeof(struct Func) % alignment;
  return remainder ? sizeof(struct Func) + alignment - remainder
                   : sizeof(struct Func);
}

static void *_context(Func function) =>
  (unsigned char *) function + _context_offset();

/* Constructors accept canonical `((func (ptype ...)) rtype ...)` Lists. The
   pattern checks only that outer shape; compiler-generated adapters
   interpret the parameters and result. A failure after allocation frees the
   partially built Func. */
static Func _new(
  FuncAdapter adapter, List signature, int rest,
  const void *context, size_t context_size) {
  if (rest && !signature.match(%((func (("List"))) ?result)))
    raise %(bad-sig (sig $signature));
  if (!adapter) raise %(bad-sig (sig $signature));
  List params = NULL;
  match (signature)
    case %((func (!set ?captured (!is type list))) ?):
      params = captured;
  if (!params) raise %(bad-sig (sig $signature));
  if (context_size && !context)
    raise %(bad-arg (operation "Func.new_context"));
  size_t context_offset = _context_offset();
  if (context_size > SIZE_MAX - context_offset)
    raise %(size-limit (operation "Func.new_context")
                       (size $context_size));
  int void_params = params.len() == 1 && params.car() is <list> &&
                    params.car() == %(void);
  size_t bytes = context_offset + context_size;
  Func fn = Scope.calloc(1, bytes), result = NULL;
  defer if (!result) Scope.free(fn);
  fn.sig = signature;
  fn.params = void_params ? NULL : params;
  fn.adapter = adapter;
  fn.rest = rest;
  fn.context_size = context_size;
  for (List p = void_params ? NULL : params; p; p = p.cdr()) fn.nparams++;
  if (context_size) memcpy(_context(fn), context, context_size);
  result = fn;
  return result;
}

/** Builds a fixed-arity native-function binding in the current `Scope`.
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

/** Builds a native-function binding that takes any number of value arguments.
    The signature declares one `List` parameter, and the adapter receives every
    argument in order through that `List`. `Func.apply` enforces no arity and
    conses the arguments itself. Use this for a variadic operation; a fixed one
    belongs in `Func.new`, which is faster and reports a wrong count. The
    canonical `signature` and adapter code are borrowed for the `Func`
    lifetime.
    The result belongs to the current `Scope`.
    Raises: `<bad-sig>` for a null adapter, a malformed signature, or a
    signature whose parameters are anything but one `List`, and `<alloc-fail>`
    when binding storage cannot be allocated.
*/
Func Func.new_rest(FuncAdapter adapter, List signature) =>
  _new(adapter, signature, 1, NULL, 0);

/** Builds a fixed-arity binding with copied context in the current `Scope`.
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

/** Returns borrowed read-only access to a `Func`'s copied context.
    The pointer remains valid only for the `Func`'s `Scope` lifetime and is
    NULL
    when the binding has no context.
    Raises: `<bad-arg>` for a null binding. It does not return on failure.
*/
const void *Func.context(Func function) {
  if (!function) raise %(bad-arg (operation "Func.context"));
  return function.context_size ? _context(function) : NULL;
}

/** Invokes a bound native function synchronously and returns its boxed result.
    `argv` is borrowed only for the call. Value bits are passed by value;
    reference arguments alias their caller-owned targets and may be mutated.
    A rest binding first interns one `List` containing the value arguments in
    their original order; rest arguments must not be `void`, since `List`s
    exclude `void` from their element domain.

    Raises: `<bad-arg>` for a null binding or argument storage, `<bad-arity>`
    for the wrong argument count, `<void-op>`, `<bad-types>`, `<bad-enc>`,
    `<bad-target>`, `<no-convert>`, or `<conv-range>` while converting an
    argument, `<alloc-fail>` or `<size-limit>` while packing rest arguments,
    `<bad-result>` when an adapter returns `void`, or any cause raised by the
    adapter or native target. The result has the ownership of the value the
    adapter returned. */
Var Func.apply(Func f, unsigned argc, const FuncArg *argv) {
  if (!f || (argc && !argv)) raise %(bad-arg (operation "Func.apply"));
  Var packed = void;
  FuncArg packed_argument;
  if (f.rest) {
    List rest = NULL;
    for (unsigned i = argc; i; i--) {
      if (argv[i - 1].reference_type) {
        List sig = f.sig;
        unsigned index = i - 1;
        raise %(bad-types (sig $sig) (index $index) (want value));
      }
      rest = cons(argv[i - 1].data.value, rest);
    }
    packed = rest;
    packed_argument = FuncArg.value(packed);
    argv = &packed_argument;
  }
  else if (argc != f.nparams) {
    unsigned expected = f.nparams;
    List sig = f.sig;
    raise %(bad-arity (sig $sig) (expected $expected) (actual $argc));
  }
  Var result = f.adapter(f, argv);
  if (result is void) {
    List sig = f.sig;
    raise %(bad-result (sig $sig));
  }
  return result;
}

/** Boxes `function` without copying or retaining the `Func`.
    The returned `Var` carries the same pointer and shares its `Scope`
    lifetime.
*/
Var Func.var(Func function) => Var.new(<func>, function);
