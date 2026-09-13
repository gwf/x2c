/*  iter.x -- single-pass pull iterators

    Copyright (c) 2025 Gary William Flake

    `Iter` advances one element at a time and reports exhaustion separately.
    An iterator borrows its source and callback. The caller supplies iterator
    storage, which must outlive traversal. Iterators cannot yield `void`.
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
   Pointer-bearing values retain no pointee ownership. */
struct Iter {
  Var obj;
  Var state;
  IterNextFn next;            // Status-bearing advancement callback
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


/** Initializes caller-supplied iterator storage and returns it.
    `iter` is caller-owned storage, normally a `struct Iter` local. This call
    writes `obj`, the `next` callback, and the initial `state`, and returns
    `iter`. It allocates nothing; the
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

    Storage must outlive every iterator derived from it, because a derived
    iterator keeps a pointer to its source. Never return an `Iter` built over
    locals, since the iterator would outlive the struct it names; return a
    collected `List` or `Array`, or take the storage as a parameter. One
    `struct Iter` is one live iterator, so reusing a single storage variable
    for two iterators silently overwrites the first.

    A null `iter` returns NULL.
*/
Self Iter.init(Self iter, Var obj, IterNextFn next, Var state) {
  if (!iter) return NULL;
  iter.obj = obj;
  iter.state = state;
  iter.next = next;
  return iter;
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

/** Returns `iter` unchanged as its own iterator.
    `dest` is ignored; ownership and remaining traversal state are unchanged.
*/
Iter Iter.iter(Iter x, Iter dest) {
  (void) dest;
  return x;
}
