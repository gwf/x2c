/*  array.x -- dynamic contiguous arrays of `Var` elements

    Copyright (c) 2025 Gary William Flake

    `Array` is mutable, identity-bearing contiguous `Var` storage over `Block`.
    Every constructor returns an allocated object, including for an empty
    `Array`; assignment aliases that object, while `Array.copy` makes a shallow
    independent container. `Scope` owns its allocation unless `Array.free`
    shortens the lifetime. `Array` data may contain raw `Null` but never
    `void`.

    The declared `Block` protocol supplies `Array`'s generated `truth`, `pop`,
    `free`, and `truncate` members. `Array.pop` discards the final element;
    `Array.take_last` removes and returns it.

    Indexing and slicing normalize negative positions here. Positional
    mutation preserves the object identity, and structural mutation
    invalidates outstanding iterators.
 */

#pragma once

#include "error-macros.x"
#include "array-generics.x"
#include "private-keywords.x"
static keyword loop $private.loop;
#include "common.x"

/** Holds a mutable identity-bearing sequence of non-`void` `Var` elements.
    `Array` is the same object as its `Block` view; that object and its backing
    storage belong to the `Scope` active at construction.
    Assignment aliases it;
    `Array.copy` creates a new container, but still borrows any objects
    referenced by its elements. `Array.free` invalidates all aliases.
*/
typedef Block Array;

protocol Cleanup(Array);

#include <string.h>
#include <stdarg.h>
#include <stdlib.h>
#include <limits.h>
#include <stdio.h>
#include "buffer.x"
#include "exception.x"
#include "func.x"
#include "iter.x"
#include "block.x"
#include "var.x"
#include "varconvert.x"

$array.core.family(Array, Var);

static void _size_limit(String owner, size_t size) {
  (void) owner;
  raise %(size-limit (size $size));
}
static void _bad_operation(String owner, Symbol operation) {
  (void) owner;
  raise %(bad-arg (operation "Array") (action $operation));
}
static void _bad_index(String owner, int index, size_t size) {
  (void) owner;
  raise %(bad-arg (operation "Array") (index $index) (size $size));
}
static void _bad_step(String owner, int step) {
  (void) owner;
  raise %(bad-arg (operation "Array.getslice") (step $step));
}

$array.typed.operations(Array, Var, void, 0, 1);
$array.boxed.index(Array, Var, void, 0, 1);
meta native Self Array.copy(Self);
meta native Self Array.getslice(Self, int, int, int);
meta native Self Array.setslice(Self, int, int, Self);
meta native Self Array.remslice(Self, int, int);
meta native Self Array.splice(Self, int, int, Self);
meta native int Array.find(Array, Var);
meta native int Array.count(Array, Var);
meta native int Array.indexof(Array, Var);
meta native Self Array.concat(Self, Self);
meta native Self Array.reverse(Self);
meta native Var Array.unshift(Array, Var);

/** Returns the same object as a `Block` view; no copy or transfer occurs. */
inline Block Array.block(Array x)         => (Block) x;
/** Returns the same object as an `Array` view; mutations remain shared. */
inline Array Block.array(Block x)         => (Array) x;

/** Releases the `Array` and its backing storage, invalidating every alias.
    The `Block` protocol generates the definition.
*/
meta void Array.free(Array array);

/** Resizes `arr`, truncating or appending `Null` elements as needed.
    Raises: `<size-limit>` when `size` exceeds the `Array` index domain, plus
    any cause from `Block` growth. Allocation and size failure do not return
    here. A growth failure leaves the length and existing elements unchanged.
*/
meta native void Array.resize(Array arr, size_t size) {
  if (size > INT_MAX) raise %(size-limit (size $size));
  if (size < arr.length) Block.truncate(arr, size);
  else if (size > arr.length) Block.append(arr, NULL, size - arr.length);
}

static int _int_length(Array array) {
  if (array.length > INT_MAX) {
    size_t size = array.length;
    raise %(size-limit (size $size));
  }
  return (int) array.length;
}

/** Appends exactly `element_count` variadic values to `array`.
    Values appended before a later `<void-op>`, `<size-limit>`, or
    `<alloc-fail>` remain in `array`. The caller must supply that many `Var`
    arguments.
*/
Self Array.update_n(Self array, unsigned element_count, ...) {
  va_list ap;
  va_start(ap, element_count);
  for (unsigned i = 0; i < element_count; i++) {
    Var elem = va_arg(ap, Var);
    array.push(elem);
  }
  va_end(ap);
  return array;
}

/** Updates one boxed element while preserving its Var tag. */
Var Array.updateindex(Array array, int index, Symbol op, Var rhs) {
  if (array == NULL) raise %(bad-arg (operation "Array.updateindex"));
  int requested = index, length = _int_length(array);
  index = x2c_normalize_index(index, length);
  if (index < 0)
    raise %(bad-arg (operation "Array.updateindex") (index $requested));
  if (rhs is void)
    raise %(void-op (operation "Array.updateindex") (index $requested));
  Var *arr = (Var *) array.bytes;
  return Var.update(arr[index], op, rhs);
}

/** Applies postfix `Array` element increment or decrement.
    The returned value is the original element. The slot remains unchanged if
    the index or operation is invalid.
    Raises: `<bad-arg>` for a null `Array` or invalid index,
    `<size-limit>` when
    its length cannot be indexed, or any cause from `Var.postfix`. The element
    is unchanged on failure.
*/
Var Array.postfixindex(Array array, int index, Symbol op) {
  if (array == NULL) raise %(bad-arg (operation "Array.postfixindex"));
  int requested = index, length = _int_length(array);
  index = x2c_normalize_index(index, length);
  if (index < 0)
    raise %(bad-arg (operation "Array.postfixindex") (index $requested));
  Var *arr = (Var *) array.bytes;
  return Var.postfix(arr[index], op);
}

/** Returns a new `Array` holding `func` applied to each element of `array`.
    `array` itself is untouched, and elements are passed as values. An empty
    input returns a fresh empty `Array` without invoking or checking `func`.
    The
    callback is invoked front to back and is not retained. It must not mutate
    `array` while the walk is in progress; `Func` rejects a `void` result.
    Raises: whatever `Func.apply` or `func` raises, or an allocation cause
    while constructing the result. The partial result is freed.
*/
Array Array.map(Array array, Func func) {
  Array output = [], result = NULL;
  defer if (result == NULL) output.free();
  foreach (Var item, array) output.push(func.apply_value(item));
  return result = output;
}

/** Maps `func` over corresponding elements up to the shorter `Array`.
    The callback receives left then right, runs front to back, and is not
    retained. An empty input does not invoke or check it; neither input may be
    structurally mutated during the walk.
    Raises: whatever `Func.apply` or `func` raises, or an allocation cause
    while constructing the result. The partial result is freed.
*/
Array Array.map2(Array a, Array b, Func func) {
  Array output = [], result = NULL;
  defer if (result == NULL) output.free();
  size_t an = a.len(), bn = b.len(), n = (an < bn) ? an : bn;
  for (size_t i = 0; i < n; i++) output.push(func.apply_values(a[i], b[i]));
  return result = output;
}

/** Folds `fn` over `array` from `seed`, front to back.
    A `void` seed means "no seed": the first element becomes the accumulator
    and the fold starts at the second, so folding an empty `Array` that way
    returns `void`. Elements are passed as values. Input with nothing left to
    fold does not invoke or check `fn`. The callback receives the accumulator
    then the next element and is not retained. It must not structurally mutate
    `array` during the walk. Any cause from `Func.apply` or `fn` propagates
    without changing `array`.
*/
Var Array.foldl(Array array, Var seed, Func fn) {
  size_t n = array.len(), i = 0;
  Var acc = seed;
  if (acc is void) {
    if (n == 0) return void;
    acc = array[i++];
  }
  for (; i < n; i++) acc = fn.apply_values(acc, array[i]);
  return acc;
}

static int _compare_var(Var a, Var b) => a.compare(b);
$array.typed.observe(Array, Var, _compare_var);
$array.typed.iterate(Array, Var, array);

static int _sort_compare(const void *ap, const void *bp) {
  Var a = *(const Var *) ap, b = *(const Var *) bp;
  return a.compare(b);
}

/** Sorts `array` in place in ascending order and returns that same `Array`.
    Call `Array.copy` first to preserve the original order. Ordering is
    `Var.compare`, which compares numbers numerically and `String`s, `Symbol`s,
    and `Atom`s by content. The sort is `qsort`, so it is not stable, and a
    null or one-element `array` is returned unchanged.

    ```x2c
    ~Array numbers = [5, 3, 9, 1];
    Array sorted = numbers.sort();
    printf("%s %d\n", numbers.repr(), sorted == numbers);
    ```
    Raises: causes from element comparison. The `Array` may already be
    partially
    reordered when a catch receives the cause. */
meta native Self Array.sort(Self array) {
  if (!array || array.length < 2) return array;
  qsort(array.bytes, array.length, sizeof(Var), _sort_compare);
  return array;
}

static int _sort_order(Func compare, Var left, Var right) =>
  compare.apply_values(left, right);

/** Stably sorts `array` with a borrowed synchronous comparator and returns it.
    The callback receives two values; its result converts to `int`, with a
    negative, zero, or positive result ordering the first before, equal to,
    or after the second. It must give a consistent ordering and must not
    mutate this Array. Sorting a different Array inside the callback is valid.
    Null and fewer than two elements return unchanged without a callback.
    Raises: allocation, `Func.apply`, conversion, or callback causes. Failure
    leaves the original Array unchanged; temporary storage is released.
    Callback side effects are not undone.
*/
Self Array.sort_with(Self array, Func compare) {
  if (!array || array.length < 2) return array;
  size_t count = array.length;
  Array source = $auto(array.copy());
  Array target = $auto([]);
  target.resize(count);
  for (size_t width = 1; width < count; width *= 2) {
    for (size_t base = 0; base < count; base += 2 * width) {
      size_t middle = base + width < count ? base + width : count;
      size_t end = base + 2 * width < count ? base + 2 * width : count;
      size_t left = base, right = middle;
      for (size_t index = base; index < end; index++) {
        int take_right = right < end &&
          (left == middle ||
           _sort_order(compare, source[left], source[right]) > 0);
        target[index] = take_right ? source[right++] : source[left++];
      }
    }
    Array swap = source;
    source = target;
    target = swap;
  }
  memcpy(array.bytes, source.bytes, count * sizeof(Var));
  return array;
}

static struct ArraySortEntry {
  Var key, value;
  size_t index;
};

static int _sort_key_compare(const void *ap, const void *bp) {
  const struct ArraySortEntry *a = ap, *b = bp;
  int order = a.key.compare(b.key);
  return order ? order : (a.index > b.index) - (a.index < b.index);
}

/** Stably sorts `array` by keys produced once per value, returning the Array.
    The borrowed callback runs front to back and must not mutate this Array.
    Keys use `Var.compare`; equal keys preserve the original element order.
    A null or empty Array invokes no callback. Sorting another Array inside
    the callback is valid. Raises: allocation, key comparison, `Func.apply`,
    or callback causes. Failure leaves the original Array unchanged;
    callback side effects are not undone.
*/
Self Array.sort_by(Self array, Func key) {
  if (!array || !array.length) return array;
  size_t count = array.length;
  struct ArraySortEntry *entries =
    Scope.calloc(count, sizeof(struct ArraySortEntry));
  defer Scope.free(entries);
  for (size_t index = 0; index < count; index++) {
    Var value = array[index];
    entries[index].key = key.apply_value(value);
    entries[index].value = value;
    entries[index].index = index;
  }
  qsort(entries, count, sizeof(struct ArraySortEntry), _sort_key_compare);
  for (size_t index = 0; index < count; index++)
    array[index] = entries[index].value;
  return array;
}

// binary min-heap

static void _heap_shift_up(Array heap, int i) {
  while (i > 0) {
    int p = (i - 1) / 2;
    if (heap[p] <= heap[i]) break;
    Var tmp = heap[p]; heap[p] = heap[i]; heap[i] = tmp;
    i = p;
  }
}

static void _heap_shift_down(Array heap, int i) {
  int n = _int_length(heap);
  loop {
    int l = (i * 2) + 1, r = l + 1, mini = i;
    if (l < n && heap[l] < heap[mini]) mini = l;
    if (r < n && heap[r] < heap[mini]) mini = r;
    if (mini == i) break;
    Var tmp = heap[i]; heap[i] = heap[mini]; heap[mini] = tmp;
    i = mini;
  }
}

/** Adds `val` to `heap`, an `Array` maintained as a binary min-heap.
    The heap operations arrange an `Array` as a priority queue in place, with
    no second data structure and no extra allocation. The elements stay in
    the `Array` with the smallest at index 0. Ordering is `Var.compare`, the
    same rule `Array.sort` uses.

    `heap_push` and `Array.heap_pop` maintain the invariant, but the
    positional operations do not. After a plain `Array.push`, an assignment
    through `Array.setindex`, or any slicing, call `Array.heapify` before
    popping again.

    ```x2c
    ~Array heap = [];
    heap.heap_push(30);
    heap.heap_push(10);
    heap.heap_push(20);
    printf("%s %s\n", heap.heap_pop().repr(), heap.heap_pop().repr());
    ```
    Raises: `<void-op>` when `val` is `void`, or `<size-limit>` when the heap
    cannot grow within the `Array` index domain, `<alloc-fail>` when storage
    cannot grow, or a cause from element comparison. A value or earlier swap
    may remain when comparison fails; pre-insertion failures leave the heap
    unchanged.
*/
meta native void Array.heap_push(Array heap, Var val) {
  heap.push(val);
  int n = _int_length(heap);
  _heap_shift_up(heap, n - 1);
}

/** Removes and returns the smallest element of `heap`, or `void` when it is
    empty. The remaining elements are re-heaped in O(log n), so repeated calls
    yield ascending order and draining a heap is a sort. An `Array` that never
    satisfied the heap invariant gives a meaningless answer instead of an
    error. Call `Array.heapify` first if it was not built with
    `Array.heap_push`.
    Raises: any cause reported by element comparison while restoring the heap.
    The heap may already have removed its root when a catch receives the error.
*/
meta native Var Array.heap_pop(Array heap) {
  if (!heap.len()) return void;
  Var root = heap[0], last = heap.take_last();
  if (heap.len()) {
    heap[0] = last;
    _heap_shift_down(heap, 0);
  }
  return root;
}

/** Rearranges `heap` in place so that it satisfies the min-heap invariant.
    Use this before the first `Array.heap_pop` on an `Array` that was built by
    `Array.push`, read in from somewhere else, or disturbed by a positional
    operation. It is O(n), cheaper than pushing the same elements one at a
    time.
    Raises: `<size-limit>` when `heap` exceeds the `INT_MAX` index limit that
    `Array.getindex` describes, or a cause from element comparison. Comparison
    failure may leave a partially rearranged `Array`.
*/
meta native void Array.heapify(Array heap) {
  int n = _int_length(heap);
  for (int i = (n / 2) - 1; i >= 0; i--) _heap_shift_down(heap, i);
}

/** Joins the elements of `array` into one `String` separated by `separator`.
    Elements are converted with their `str` form, so a `String` element
    contributes its bytes without quotes and a number contributes its
    digits. A null `separator` joins with nothing between elements, and an
    empty array yields the empty `String`.

    The receiver here is the `Array`. In `String.join` the separator is the
    receiver and the elements arrive as a `List`. Raises: `<alloc-fail>` or
    `<size-limit>` while rendering or canonicalizing the result, or a cause
    from an element's `write_str`. */
meta native String Array.join(Array array, String separator) {
  size_t n = array.length;
  if (n == 0) return "";
  Buffer buf = Buffer.new(0);
  for (size_t i = 0; i < n; i++) {
    Var elem = ((Var *) array.bytes)[i];
    elem.write_str(buf);
    if (separator && i < n - 1) buf.write(separator);
  }
  return buf.str_free();
}

/** Drains `iter` into a fresh `Array`. */
meta native Array Iter.array(Iter iter) {
  Array output = [], result = NULL;
  defer if (result == NULL) output.free();
  foreach (Var item, iter) output.push(item);
  return result = output;
}

/** Ends the owned lifetime when a managed local leaves its block. */
meta native void Array.cleanup(Array value) { value.free(); }
