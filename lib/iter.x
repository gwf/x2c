/*  iter.x -- single-pass pull iterators

    Copyright (c) 2025 Gary William Flake

    `Iter` advances one element at a time and reports exhaustion separately.
    Lazy operations borrow their source iterators and callbacks. The caller
    supplies iterator storage, which must outlive traversal. Iterators cannot
    yield `void`.
 */

#pragma once
$(import "error-macros.xmacro")
$(import "private-keywords.xmacro")
#include "common.x"

/** Caller-owned handle to single-pass iterator state.
    A valid handle points to storage initialized by `Iter.init` or a collection
    adapter. Its storage, borrowed sources, and stored callbacks must outlive
    traversal. The handle has no destructor; auxiliary `Map` or `Array` storage
    follows the lifetime of its owning `Scope`.
*/
typedef struct Iter *Iter;

/** Advances an `Iter`, reporting success separately from the element.
    The iterator borrows the callback and invokes it synchronously. A nonzero
    result must write one non-`void` value through `out`; zero reports
    exhaustion and must leave `out` unchanged.
*/
typedef int (*IterNextFn)(Iter iter, Var *out);

/* `obj` and `state` are callback-owned carriers: each producer installs and
   decodes its own pointer, counter, aggregate, or packed word representation.
   Pointer-bearing values and `aux` retain no pointee ownership. */
struct Iter {
  Var obj;
  Var state;
  IterNextFn next;            // Status-bearing advancement callback
  Func aux;                   // Callback state for lazy pipeline stages
};

/** Caller-owned buffering shared by the two iterators from `Iter.unzip`.
    Its source and this record must outlive both columns. `Buffer` allocations
    belong to the `Scope` that owns the `Array`s created at
    initialization; that
    `Scope` must remain live through all column pulls and provides cleanup.
*/
typedef struct UnzipShared UnzipShared;

/** Internal column selector embedded in `UnzipShared`.
    Callers reserve it as part of that shared record and do not initialize or
    use it independently.
*/
typedef struct {
  UnzipShared *shared, int column;
} UnzipColumn;

struct UnzipShared {
  Iter source, Array buffers[2], int heads[2], done;
  UnzipColumn columns[2];
  struct Iter column_iters[2];
};

#pragma private

#include "list.x"
#include "var.x"
#include "symbol.x"
#include "scope.x"
#include "array.x"
#include "block.x"
#include "func.x"
#include <limits.h>
#include <stdlib.h>

#define UNZIP_COMPACT_THRESHOLD 256

typedef UnzipColumn *UnzipColumnRef;
typedef UnzipShared *UnzipSharedRef;

/* Protocol resolution runs before macro expansion, so these converter
   declarations and the adoption rows below must remain literal. */
static inline Var UnzipColumnRef.var(UnzipColumnRef);
static inline UnzipColumnRef Var.unzipcolumnref(Var);
static inline Var UnzipSharedRef.var(UnzipSharedRef);
static inline UnzipSharedRef Var.unzipsharedref(Var);

/* Unzip state remains caller-owned. These definitions only name the pointers
   crossing through Iter.obj and preserve their raw <p48> bits. */
$(import "var-adapters.xmacro")
$var.raw.pointer(UnzipColumnRef, unzipcolumnref);
$var.raw.pointer(UnzipSharedRef, unzipsharedref);

protocol Var(UnzipColumnRef) as void *;
protocol Var(UnzipSharedRef) as void *;

/** Initializes caller-supplied iterator storage and returns it.
    `iter` is caller-owned storage, normally a `struct Iter` local. This call
    writes `obj`, the `next` callback, and the initial `state`, clears the
    auxiliary callback slot, and returns `iter`. It allocates nothing; the
    iterator lives as long as the supplied storage.

    A callback fills `*out` and returns 1, or returns 0 to report
    exhaustion. It must never report success with `void`, which the element
    domain excludes. `Iter.try_next` raises `<void-op>` for that violation. A
    null `next` yields an already-exhausted iterator. Inside a callback, read
    the stored fields with `->`; `iter.next(...)` is receiver syntax and calls
    the method instead of the field.

    ```x2c
    ~static int _evens_next(Iter iter, Var *out) {
    ~  long value = iter.state.long();
    ~  if (value > iter.obj.long()) return 0;
    ~  *out = (int) value;
    ~  iter.state = value + 2;
    ~  return 1;
    ~}
    ~
    ~int main(void) {
    struct Iter storage;
    Iter evens = Iter.init(&storage, 6, _evens_next, 0);
    Var value;
    while (evens.try_next(&value)) printf("%d\n", value);
    ~  return 0;
    ~}
    ```

    Storage must outlive every iterator derived from it, because a pipeline
    stage keeps a pointer to its source. Never return an `Iter` built over
    locals, since the iterator would outlive the struct it names; return a
    collected `List` or `Array`, or take the storage as a parameter. One
    `struct Iter` is one live iterator, so reusing a single storage variable
    for two stages of a pipeline silently overwrites the first.

    A null `iter` returns NULL.
*/
Self Iter.init(Self iter, Var obj, IterNextFn next, Var state) {
  if (!iter) return NULL;
  iter.obj = obj;
  iter.state = state;
  iter.next = next;
  iter.aux = NULL;
  return iter;
}

static void _unzip_buffer_push(UnzipShared *shared, Var pair) {
  if (pair is not <list>)
    raise %(bad-types (owner "Iter.unzip") (want "two-element List")
            (value $pair));
  List list = pair;
  if (!list || !list.cdr() || list.cdr().cdr())
    raise %(bad-arg (owner "Iter.unzip") (want "two-element List")
            (value $pair));
  Var (first, second) = list;
  shared.buffers[0].push(first);
  shared.buffers[1].push(second);
}

static void _unzip_compact(UnzipShared *shared, int column) {
  int consumed = shared.heads[column];
  if (consumed < UNZIP_COMPACT_THRESHOLD) return;
  Array removed = shared.buffers[column].remslice(0, consumed);
  removed.free();
  shared.heads[column] = 0;
}

static int _unzip_ensure(UnzipShared *shared, int column) {
  while (shared.heads[column] >= shared.buffers[column].len()) {
    if (shared.done) return 0;
    Var pair;
    if (!shared.source.try_next(&pair)) {
      shared.done = 1;
      return 0;
    }
    _unzip_buffer_push(shared, pair);
  }
  return 1;
}

/** Advances `iter`, writing the next element through `out`.
    Returns nonzero when it produced an element and zero once the iterator
    is exhausted, and writes `out` only in the nonzero case. Prefer this
    form. Status travels separately from the payload, so no value is reserved
    to mean "finished".

    An `Iter` is single-pass. There is no rewind, so build a fresh iterator
    when you need a second traversal.

    ```x2c
    ~int main(void) {
    struct Iter storage;
    Iter counts = range(3, 1, -1, &storage);
    Var value;
    while (counts.try_next(&value)) printf("%d\n", value);
    ~  return 0;
    ~}
    ```
    Raises: `<void-op>` when a source callback claims success with a `void`
    element, plus any cause raised by that callback. A null `iter` or `out`
    reads as exhausted without raising.
*/
int Iter.try_next(Iter iter, Var *out) {
  if (!iter || !out || !iter->next) return 0;
  /* Arrow syntax calls the stored callback. A receiver call here would
     recursively select Iter.next. */
  if (!iter->next(iter, out)) {
    iter->next = NULL;
    return 0;
  }
  if (out[0] is void) raise %(void-op (owner "Iter.try_next"));
  return 1;
}

/** Returns the next element, or `void` once `iter` is exhausted.
    An adapter over `Iter.try_next`, unambiguous because no iterator may
    yield `void` as an element. Prefer `Iter.try_next` in new code; it reports
    exhaustion separately from the element.
    Raises: `<void-op>` when the source callback claims success with `void`,
    plus any cause raised by that callback.
*/
Var Iter.next(Iter iter) {
  Var out;
  return iter.try_next(&out) ? out : void;
}

static Var _range_raw_int(int value) =>
  (Var) { .u64 = (unsigned long) ((long long) value - INT_MIN) };

static int _range_raw_value(Var value) =>
  (int) ((long long) (unsigned) value.u64 + INT_MIN);

/* Range packs the full native int domain into Iter's two Var-sized carrier
   words without allocating an auxiliary state object. The unit-step forms
   store one offset integer per word; the general form packs `end` above
   `step`. These raw words stay inside range callbacks and never enter Var
   dispatch or escape as yielded values. */
static Var _range_raw_pair(int high, int low) {
  unsigned long upper = (unsigned) ((long long) high - INT_MIN);
  unsigned lower = (unsigned) ((long long) low - INT_MIN);
  return (Var) { .u64 = (upper << 32) | lower };
}

static int _range_raw_high(Var value) {
  unsigned high = (unsigned) (value.u64 >> 32);
  return (int) ((long long) high + INT_MIN);
}

static int _range_up_next(Iter iter, Var *out) {
  int result = _range_raw_value(iter.state), stop = _range_raw_value(iter.obj);
  if (result > stop) return 0;
  *out = result;
  if (result == stop) iter->next = NULL;
  else iter.state = _range_raw_int(result + 1);
  return 1;
}

static int _range_down_next(Iter iter, Var *out) {
  int result = _range_raw_value(iter.state), stop = _range_raw_value(iter.obj);
  if (result < stop) return 0;
  *out = result;
  if (result == stop) iter->next = NULL;
  else iter.state = _range_raw_int(result - 1);
  return 1;
}

static int _range_general_next(Iter iter, Var *out) {
  int stop = _range_raw_high(iter.obj);
  int step = _range_raw_value(iter.obj);
  int result = iter.state.int();
  if ((step > 0 && result > stop) || (step < 0 && result < stop)) return 0;
  *out = result;
  long long next = (long long) result + step;
  if ((step > 0 && next > stop) || (step < 0 && next < stop) ||
      next > INT_MAX || next < INT_MIN)
    iter->next = NULL;
  else iter.state = (int) next;
  return 1;
}

/** Returns an inclusive integer range over caller-supplied `iter` storage.
    Both endpoints belong to the range when the step direction reaches them:
    `range(1, 4, 1, &storage)` yields 1, 2, 3, 4, and `range(3, 1, -1,
    &storage)` counts down 3, 2, 1. A step that would cross `end` stops short
    of it, so `range(0, 9, 2, &storage)` yields 0, 2, 4, 6, 8. A range
    pointed against its step is empty. A range needs no state struct and no
    cleanup.
    Raises: `<bad-arg>` when `step` is zero. A null `iter` returns NULL
    without raising.
*/
Iter range(int start, int end, int step, Iter iter) {
  if (!iter) return NULL;
  if (!step) raise %(bad-arg (owner "range") (step $step));
  if (step == 1)
    return iter.init(
      _range_raw_int(end), _range_up_next, _range_raw_int(start));
  if (step == -1)
    return iter.init(
      _range_raw_int(end), _range_down_next, _range_raw_int(start));
  return iter.init(_range_raw_pair(end, step), _range_general_next, start);
}

static Var _apply1(Func fn, Var value) {
  FuncArg arguments[1] = { FuncArg.value(value) };
  return fn.apply(1, arguments);
}

static Var _apply2(Func fn, Var left, Var right) {
  FuncArg arguments[2] = {
    FuncArg.value(left), FuncArg.value(right)
  };
  return fn.apply(2, arguments);
}

static int _filter_next(Iter iter, Var *out) {
  Iter source = iter.obj;
  Func func = iter.aux;
  if (!source || !func) return 0;
  foreach (Var value, source) {
    if (_apply1(func, value)) {
      *out = value;
      return 1;
    }
  }
  return 0;
}

/** Returns a lazy iterator over elements accepted by `func`'s `Var`
    truthiness.
    The predicate fits in `dest`, so that storage is all you declare.
    Rejected elements are consumed without being yielded, so one request for
    an element can pull many from the source.

    Elements are passed as values. Both `iter` and its storage, `dest`, and any
    dynamic or captured `func` must remain valid while the result is used.

    A null `dest` returns NULL, and a null `func` yields an
    exhausted iterator. An empty source does not invoke or check `func`.
    Raises: whatever the source, `Func.apply`, or `func` raises while pulling.
*/
Iter Iter.filter(Iter iter, Func func, Iter dest) {
  if (!dest) return NULL;
  dest.init(iter, _filter_next, void);
  dest.aux = func;
  return dest;
}

static int _map_next(Iter iter, Var *out) {
  Iter source = iter.obj;
  if (!source || !source.try_next(out)) return 0;
  if (iter.aux) *out = _apply1(iter.aux, *out);
  return 1;
}

/** Returns a lazy iterator over `func` applied to each element of `iter`.
    `dest` is caller-owned `struct Iter` storage. It and the source iterator's
    storage, plus any dynamic or captured `func`, must remain valid while the
    result is used. Elements are passed as values. Nothing runs until an
    element is pulled, and each pull travels back up the chain for exactly one
    element per stage, so taking two elements from a map over a range calls
    `func` twice. A null `func` passes elements through unchanged.

    ```x2c
    ~static Var _square(Var value) {
    ~  return value * value;
    ~}
    ~
    ~int main(void) {
    struct Iter source_storage, map_storage;
    Iter squares = range(1, 4, 1, &source_storage).map(_square,
                                                      &map_storage);
    printf("%s\n", squares.list().str());
    ~  return 0;
    ~}
    ```

    A null `dest` returns NULL. An empty source does not invoke or check
    `func`. Raises: whatever the source, `Func.apply`, or `func` raises while
    pulling, including `<bad-result>` when `func` returns `void`.
*/
Iter Iter.map(Iter iter, Func func, Iter dest) {
  if (!dest) return NULL;
  dest.init(iter, _map_next, void);
  dest.aux = func;
  return dest;
}

static int _zip_next(Iter iter, Var *out) {
  Iter left_iter = iter.obj, right_iter = iter.state;
  if (!left_iter || !right_iter) return 0;
  Var left, right;
  if (!left_iter.try_next(&left) || !right_iter.try_next(&right)) return 0;
  *out = %($left $right);
  return 1;
}

/** Returns a lazy iterator over canonical `(left right)` `List`s.
    Destructure each pair with `Var (a, b) = pair;`. Pairing
    ends as soon as either source does. Each pull advances the left side first:
    if the right side is exhausted, that unmatched left value is consumed; if
    the left side is exhausted, the right side is not pulled. Both sources and
    `dest` must outlive traversal. Each yielded pair follows the lifetime of
    the `List` pool owning its canonical match.

    Raises: `<alloc-fail>` or `<size-limit>` while interning a pair, plus any
    cause raised by either source. A null `dest` returns NULL.
*/
Iter Iter.zip(Iter left, Iter right, Iter dest) {
  if (!dest) return NULL;
  return dest.init(left, _zip_next, right);
}

static int _zip_with_next(Iter iter, Var *out) {
  Iter left_iter = iter.obj, right_iter = iter.state;
  if (!left_iter || !right_iter) return 0;
  Var left, right;
  if (!left_iter.try_next(&left) || !right_iter.try_next(&right)) return 0;
  if (iter.aux) *out = _apply2(iter.aux, left, right);
  else *out = %($left $right);
  return 1;
}

/** Returns a lazy iterator over `fn(left, right)`, applied pairwise.
    Like `Iter.zip`, but each pair is combined by `fn` instead of being
    built into a `List`, and the result likewise ends with the shorter side.
    `fn` is optional. A null `fn` yields two-element pair `List`s as `Iter.zip`
    does. `Iter.map2` is the same operation with the callback required.

    Both sources and their storage, `dest`, and any dynamic or captured `fn`
    must remain valid while the result is used. Values are passed, not aliases
    into either source. A null `dest` returns NULL. If either source is empty,
    pulling does not invoke or check `fn`.
    Raises: whatever either source, `Func.apply`, or `fn` raises while
    pulling. With a null `fn`, pair interning may raise `<alloc-fail>` or
    `<size-limit>`.
*/
Iter Iter.zip_with(Iter left, Iter right, Func fn, Iter dest) {
  if (!dest) return NULL;
  dest.init(left, _zip_with_next, right);
  dest.aux = fn;
  return dest;
}

/** Returns a lazy iterator over `fn(left, right)`, requiring `fn`.
    The strict form of `Iter.zip_with`. Behavior is identical, except that a
    null `fn` returns NULL instead of yielding pairs. Use it when a missing
    callback should fail at construction instead of changing the element
    type.

    The sources, destination, callback lifetime, value passing, and pull-time
    failures are those of `Iter.zip_with`. A null `fn` or `dest` returns NULL.
*/
Iter Iter.map2(Iter left, Iter right, Func fn, Iter dest) {
  if (!fn) return NULL;
  return left.zip_with(right, fn, dest);
}

static int _chain_next(Iter iter, Var *out) {
  Iter current = iter.obj;
  if (current && current.try_next(out)) return 1;
  current = iter.state;
  iter.obj = current;
  iter.state = void;
  return current && current.try_next(out);
}

/** Returns a lazy iterator over `first` followed by `second`.
    Pulls do not reach `second` until `first` is exhausted. Both sources and
    `dest` are borrowed and must outlive traversal. A null source contributes
    no elements, and a null `dest` returns NULL. Pulling may raise any cause
    raised by either source.
*/
Iter Iter.chain(Iter first, Iter second, Iter dest) {
  if (!dest) return NULL;
  return dest.init(first, _chain_next, second);
}

static int _enumerate_next(Iter iter, Var *out) {
  Iter source = iter.obj;
  if (!source) return 0;
  Var value;
  if (!source.try_next(&value)) return 0;
  int index = iter.state;
  iter.state = index + 1;
  *out = %($index $value);
  return 1;
}

/** Returns a lazy iterator over `(index value)` `List`s starting at `start`.
    The first pulled value is paired with exactly `start`, then the native
    `int` index increases by one for each source value. The source and `dest`
    are borrowed and must outlive traversal; `start` plus the number of
    successfully pulled values must remain within the `int` range.

    Raises: `<alloc-fail>` or `<size-limit>` while interning a pair, plus any
    cause raised by the source. A null `dest` returns NULL.
*/
Iter Iter.enumerate(Iter iter, int start, Iter dest) {
  if (!dest) return NULL;
  return dest.init(iter, _enumerate_next, start);
}

static int _repeat_next(Iter iter, Var *out) {
  int remaining = iter.state;
  if (remaining <= 0) return 0;
  iter.state = remaining - 1;
  *out = iter.obj;
  return 1;
}

/** Returns a lazy iterator that yields `value` at most `count` times.
    A nonpositive count yields nothing. `dest` is caller-owned, and any
    storage referenced by `value` must outlive traversal. A null `dest`
    returns NULL. Pulling a repeated `void` raises `<void-op>`.
*/
Iter Iter.repeat(Var value, int count, Iter dest) {
  if (!dest) return NULL;
  return dest.init(value, _repeat_next, count > 0 ? count : 0);
}

static int _head_next(Iter iter, Var *out) {
  Iter source = iter.obj;
  int remaining = iter.state;
  if (!source || remaining <= 0) return 0;
  if (!source.try_next(out)) return 0;
  iter.state = remaining - 1;
  return 1;
}

/** Returns a lazy iterator over at most `count` leading source values.
    Construction consumes nothing. Pulling stops after `count` values or
    source exhaustion, whichever comes first, and leaves any later source
    values unconsumed. A nonpositive count yields nothing. The source and
    caller-owned `dest` must outlive traversal; a null `dest` returns NULL.
    Pulling may raise any cause raised by the source.
*/
Iter Iter.head(Iter iter, int count, Iter dest) {
  if (!dest) return NULL;
  return dest.init(iter, _head_next, count > 0 ? count : 0);
}

static int _accumulate_next(Iter iter, Var *out) {
  Iter source = iter.obj;
  if (!source) return 0;
  Var item;
  if (!source.try_next(&item)) return 0;
  iter.state = iter.state.binary(<+>, item);
  *out = iter.state;
  return 1;
}

/** Returns a lazy iterator over the running numeric sum of `iter`.
    The numeric special case of `Iter.scan`. Each element is added through
    `Var.binary` with the same promotion and failure rules as `Iter.sum`, and
    the resulting `Var` is yielded without narrowing. A `void`
    `initial` starts the total at integer zero; any other `initial` seeds it,
    and the seed itself is never yielded. Prefer `Iter.scan` for a different
    operation and `Iter.sum` when only the final total matters.

    Raises: any cause from the source or `Var.binary` while adding an element
    to the running total. A null `dest` returns NULL without raising.
*/
Iter Iter.accumulate(Iter iter, Var initial, Iter dest) {
  if (!dest) return NULL;
  return dest.init(
    iter, _accumulate_next, initial is void ? (Var) 0 : initial);
}

static int _scan_next(Iter iter, Var *out) {
  Iter source = iter.obj;
  if (!source || !iter.aux) return 0;
  Var item;
  if (!source.try_next(&item)) return 0;
  iter.state = _apply2(iter.aux, iter.state, item);
  *out = iter.state;
  return 1;
}

/** Returns a lazy iterator over every new accumulator of `fn`.
    Each step computes `fn(accumulator, element)`, keeps the result as the new
    accumulator, and yields it. `seed` is the initial accumulator and is never
    yielded, so a scan produces exactly as many elements as its source. `fn`
    is required. The accumulator and each element are passed as values.

    ```x2c
    ~static Var _add(Var acc, Var item) {
    ~  return acc + item;
    ~}
    ~
    ~int main(void) {
    struct Iter source_storage, scan_storage;
    Iter running = range(1, 4, 1, &source_storage).scan(0, _add,
                                                       &scan_storage);
    foreach (int total, running) printf("%d\n", total);
    ~  return 0;
    ~}
    ```

    That prints 1, 3, 6, and 10; the seed 0 never appears.

    The source and its storage, `dest`, and any dynamic or captured `fn` must
    remain valid while the result is used. Constructing the iterator does not
    invoke `fn`. Pulling may raise whatever `Func.apply`, the source, or `fn`
    raises, including `<bad-result>` when `fn` returns `void`. A null `fn` or
    `dest` returns NULL.
*/
Iter Iter.scan(Iter iter, Var seed, Func fn, Iter dest) {
  if (!dest || !fn) return NULL;
  dest.init(iter, _scan_next, seed);
  dest.aux = fn;
  return dest;
}

static int _unique_next(Iter iter, Var *out) {
  Iter source = iter.obj;
  Map seen = iter.state;
  if (!source) return 0;
  loop {
    Var value;
    if (!source.try_next(&value)) return 0;
    if (!seen.contains(value)) {
      seen[value] = value;
      *out = value;
      return 1;
    }
  }
}

/** Returns a lazy iterator that yields the first occurrence of each value.
    Equality and hashing follow `Map`, so source order decides which equal
    value survives. Construction allocates a `Scope`-owned seen table; pulls
    may
    grow it. The source, `dest`, and owning `Scope` must outlive traversal.

    Raises: `<alloc-fail>`, `<size-limit>`, `<invariant>`, or a cause from the
    source, hashing, or equality while constructing or pulling. A null `dest`
    returns NULL without allocating.
*/
Iter Iter.unique(Iter iter, Iter dest) {
  if (!dest) return NULL;
  return dest.init(iter, _unique_next, %{});
}

static int _unzip_column_next(Iter iter, Var *out) {
  UnzipColumnRef state = iter.obj.unzipcolumnref();
  if (!state) return 0;
  UnzipShared *shared = state.shared;
  if (!_unzip_ensure(shared, state.column)) return 0;
  *out = shared.buffers[state.column][shared.heads[state.column]];
  shared.heads[state.column] += 1;
  _unzip_compact(shared, state.column);
  return 1;
}

static void _unzip_shared_init(UnzipShared *u, Iter source) {
  if (!u) return;
  u->source = source;
  u->buffers[0] = %[];
  u->buffers[1] = %[];
  u->heads[0] = u->heads[1] = 0;
  u->done = 0;
  for (int i = 0; i < 2; i++) {
    u->columns[i].shared = u;
    u->columns[i].column = i;
    Iter.init(
      &u->column_iters[i], (UnzipColumnRef) &u->columns[i],
      _unzip_column_next, 1);
  }
}

static int _unzip_next(Iter iter, Var *out) {
  UnzipSharedRef shared = iter.obj.unzipsharedref();
  if (!shared) return 0;
  int stage = (int) iter.state.long();
  if (stage >= 2) return 0;
  Iter child = &shared.column_iters[stage];
  iter.state = stage + 1;
  *out = child;
  return 1;
}

/** Returns an iterator over the two column iterators of paired elements.
    Every element of `iter` must be a two-element `List`. The result yields
    two elements, the left column and then the right one, and is exhausted
    after that. Each column arrives as a `Var` holding an iterator
    embedded in `shared`. Passing nonnull storage to `.iter(&storage)` performs
    the `Var` conversion, but `Iter.iter` ignores that storage and returns the
    embedded column; `shared` remains its owner.

    The columns are independent, and only the lag between them is buffered.
    Draining one column holds every element the other has not reached yet, so
    interleaving the two costs little and front-loading one costs memory
    proportional to the source. `shared` owns those buffers and must outlive
    both columns.

    ```x2c
    ~int main(void) {
    List pairs = %((1 10) (2 20));
    struct Iter source_storage, columns_storage, left_storage, right_storage;
    UnzipShared shared;
    Iter columns = pairs.iter(&source_storage).unzip(&shared,
                                                    &columns_storage);
    Iter lefts = columns.next().iter(&left_storage);
    Iter rights = columns.next().iter(&right_storage);
    printf("%s %s\n", lefts.list().str(), rights.list().str());
    ~  return 0;
    ~}
    ```
    Raises: `<bad-types>` when an element is not a `List`, `<bad-arg>` when it
    is not a two-element `List`, or `<alloc-fail>` / `<size-limit>` while
    creating or growing the column buffers. A source may also raise while a
    column pulls. A null `shared` or `dest` returns NULL without raising or
    allocating.
*/
Iter Iter.unzip(Iter iter, UnzipShared *shared, Iter dest) {
  if (!shared || !dest) return NULL;
  _unzip_shared_init(shared, iter);
  return dest.init((UnzipSharedRef) shared, _unzip_next, 0);
}

/** Folds `func` over `iter` and returns the final accumulator.
    Consumes the whole iterator. A `void` `initial` means "use the first
    element as the seed", so a reduce over an empty iterator returns `void`;
    any other `initial` is the seed and is returned unchanged when there is
    nothing to fold. A null `func` drains the iterator and returns the
    seed.
    The accumulator and elements are passed as values. Empty input, or one
    element with a `void` initial value, does not invoke or check `func`.
    Raises: whatever the source, `Func.apply`, or `func` raises.
*/
Var Iter.reduce(Iter iter, Func func, Var initial) {
  Var acc = initial, item;
  int has_item = iter.try_next(&item);
  if (acc is void) {
    if (!has_item) return void;
    acc = item;
    has_item = iter.try_next(&item);
  }
  if (!func) {
    while (has_item) has_item = iter.try_next(&item);
    return acc;
  }
  while (has_item) {
    acc = _apply2(func, acc, item);
    has_item = iter.try_next(&item);
  }
  return acc;
}

/** Folds `fn` over `iter` from `seed`, left to right.
    `Iter.reduce(fn, seed)` with the seed first and the combining function
    second. Every rule of `Iter.reduce` applies, including the `void` seed
    rule.
    Raises: whatever the source, `Func.apply`, or `fn` raises.
*/
Var Iter.foldl(Iter iter, Var seed, Func fn) => iter.reduce(fn, seed);

/** Reports whether any remaining element satisfies `pred`.
    Stops at the first element the predicate accepts, so the iterator is left
    positioned after it and the rest is never pulled. An empty iterator
    answers 0. Elements are passed as values and the result uses ordinary `Var`
    truthiness.
    Raises: whatever the source, `Func.apply`, or `pred` raises. A null
    `pred` answers 0.
*/
int Iter.any(Iter iter, Func pred) {
  if (!pred) return 0;
  foreach (Var item, iter) {
    if (_apply1(pred, item)) return 1;
  }
  return 0;
}

/** Reports whether every remaining element satisfies `pred`.
    Vacuously true for an empty iterator, decided before `pred` is consulted.
    Otherwise it stops at the first element the predicate
    rejects and answers 0, leaving the rest unconsumed. Elements are passed as
    values and the result uses ordinary `Var` truthiness.
    Raises: whatever the source, `Func.apply`, or `pred` raises. A null `pred`
    answers 1 for an empty iterator and 0 for any other.
*/
int Iter.all(Iter iter, Func pred) {
  Var item;
  if (!iter.try_next(&item)) return 1;
  if (!pred) return 0;
  do {
    if (!_apply1(pred, item)) return 0;
  }
  while (iter.try_next(&item));
  return 1;
}

/** Returns the first element accepted by `pred`'s `Var` truthiness, else
    `void`.
    Stops as soon as it finds one, so the iterator can be pulled further for
    the elements after the match. `void` means "no element matched", which is
    unambiguous because no iterator may yield `void`.
    Elements are passed as values. Raises: whatever the source, `Func.apply`,
    or `pred` raises. A null `pred` returns `void`.
*/
Var Iter.find(Iter iter, Func pred) {
  if (!pred) return void;
  foreach (Var item, iter) {
    if (_apply1(pred, item)) return item;
  }
  return void;
}

/** Returns the number of remaining elements, consuming `iter`.
    Counting drains the iterator, and an `Iter` cannot be rewound, so if you
    need the elements as well, collect them with `Iter.list` or `Iter.array`
    and ask the collection for its length. The remaining element count must
    fit in `int`.
    Raises: `<void-op>` for a source callback that yields `void`, plus any
    cause raised by that callback.
*/
int Iter.count(Iter iter) {
  int total = 0;
  Var item;
  while (iter.try_next(&item)) total++;
  return total;
}

/** Returns the sum of the remaining elements, consuming `iter`.
    Starts from the integer 0 and adds with ordinary `Var` arithmetic, so
    numeric element types promote as they would in an expression and an empty
    iterator sums to 0. Use `Iter.accumulate` for the running totals.
    Raises: any cause from the source or `Var.binary` while adding an element
    to the running total.
*/
Var Iter.sum(Iter iter) {
  Var total = 0;
  foreach (Var item, iter) total = total.binary(<+>, item);
  return total;
}

/** Returns the product of the remaining elements, consuming `iter`.
    Starts from the integer 1 and multiplies with ordinary `Var` arithmetic,
    so an empty iterator produces 1 and numeric types promote as they would in
    an expression. Integer results wrap to `Var.binary`'s promoted type width.
    Raises: any cause from the source or `Var.binary` while multiplying an
    element into the running product.
*/
Var Iter.product(Iter iter) {
  Var total = 1;
  foreach (Var item, iter) total = total.binary(<*>, item);
  return total;
}

/** Returns the largest remaining element, or `void` when there is none.
    Consumes the iterator, comparing with `Var` ordering, which is total
    across types. Equal values keep the earliest, so the result is the first
    of any tie.
    Raises: `<void-op>` for a source callback that yields `void`, plus any
    cause from the source or `Var.compare`.
*/
Var Iter.max(Iter iter) {
  Var best;
  if (!iter.try_next(&best)) return void;
  foreach (Var item, iter) if (item > best) best = item;
  return best;
}

/** Returns the smallest remaining element, or `void` when there is none.
    Consumes the iterator, comparing with `Var` ordering, which is total
    across types. Equal values keep the earliest, so the result is the first
    of any tie.
    Raises: `<void-op>` for a source callback that yields `void`, plus any
    cause from the source or `Var.compare`.
*/
Var Iter.min(Iter iter) {
  Var best;
  if (!iter.try_next(&best)) return void;
  foreach (Var item, iter) if (item < best) best = item;
  return best;
}

/** Returns `iter` unchanged as its own iterator.
    `dest` is ignored; ownership and remaining traversal state are unchanged.
*/
Iter Iter.iter(Iter x, Iter dest) {
  (void) dest;
  return x;
}
