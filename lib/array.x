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

$(import "error-macros.xmacro")
$(import "array-generics.xmacro")
$(import "private-keywords.xmacro")
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

#pragma private
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

/** Returns the same object as a `Block` view; no copy or transfer occurs. */
inline Block Array.block(Array x)         => (Block) x;
/** Returns the same object as an `Array` view; mutations remain shared. */
inline Array Block.array(Block x)         => (Array) x;

/** Returns a fresh empty `Array` with its own identity.
    The literal `%[]` calls this constructor. Test emptiness with `Array.len`.
    Raises: `<alloc-fail>` if the backing `Block` cannot be allocated.
*/
Array Array.new(void) => Block.new(sizeof(Var));

/** Resizes `arr`, truncating or appending `Null` elements as needed.
    Raises: `<size-limit>` when `size` exceeds the `Array` index domain, plus
    any cause from `Block` growth. Allocation and size failure do not return
    here. A growth failure leaves the length and existing elements unchanged.
*/
void Array.resize(Array arr, size_t size) {
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

// void terminates value protocols and is never Array data
static inline void _require_array_value(Var value) {
  if (value is void) raise %(void-op);
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

/** Returns the element at `index`, or `void` when `index` is out of range.
    This is what `array[index]` lowers to. A negative `index` counts from
    the end, so `-1` is the last element and `-array.len()` is the first.
    An index that still falls outside the array after that normalization
    yields `void`.

    `Array` has no `Array.try_get`; the `void` result reports the miss. It is
    unambiguous because `void` is excluded from the element domain. Raw `Null`
    is `Array` data and reads back as itself.

    Compound assignment and increment/decrement on an indexed `Array` become
    single calls to `Array.updateindex` and `Array.postfixindex`. The read,
    modify, and write happen in one call. That is not thread-safe
    synchronization.

    ```x2c
    ~Array digits = %[0, 1, 2, 3, 4, 5];
    printf("%s %s\n", digits[0].repr(), digits[-1].repr());
    printf("%s %s\n", digits[6].repr(), digits[-7].repr());
    ```
    Raises: `<size-limit>` when `array` holds more than `INT_MAX` elements.
*/
Var Array.getindex(Array array, int index) {
  int length = _int_length(array);
  index = x2c_normalize_index(index, length);
  if (index < 0) return void;
  Var *arr = (Var *) array.bytes;
  return arr[index];
}

/** Stores `elem` at `index` and returns it, or `void` when out of range.
    This is what `array[index] = elem` lowers to. Negative indices count
    from the end as in `Array.getindex`. An out-of-range index changes
    nothing and is reported by the `void` result. `setindex` never grows the
    array; use `Array.push` or `Array.insert` to add an element.

    The bounds check runs before the value check, so an out-of-range write
    of `void` returns `void` instead of failing.
    Raises: `<void-op>` when `elem` is `void` and `index` is in range, or
    `<size-limit>` when `array` exceeds the `INT_MAX` index limit that
    `Array.getindex` describes.
*/
Var Array.setindex(Array array, int index, Var elem) {
  int length = _int_length(array);
  index = x2c_normalize_index(index, length);
  if (index < 0) return void;
  _require_array_value(elem);
  Var *arr = (Var *) array.bytes;
  arr[index] = elem;
  return elem;
}

/** Updates one `Array` element in place.
    The index is normalized once, including negative indexing, and the
    element slot is delegated to `Var.update`. The stored `Var` tag is
    therefore preserved and the slot remains unchanged on failure.
    Raises: `<bad-arg>` for a null `Array` or invalid index,
    `<size-limit>` when
    its length cannot be indexed, `<void-op>` for a `void` right operand, or
    any cause from `Var.update`. These failures leave the element unchanged
   .
*/
Var Array.updateindex(Array array, int index, Symbol op, Var rhs) {
  if ((void *) array == NULL) raise %(bad-arg (owner "Array.updateindex"));
  int requested = index, length = _int_length(array);
  index = x2c_normalize_index(index, length);
  if (index < 0)
    raise %(bad-arg (owner "Array.updateindex") (index $requested));
  if (rhs is void)
    raise %(void-op (owner "Array.updateindex") (index $requested));
  Var *arr = (Var *) array.bytes;
  return Var.update(arr + index, op, rhs);
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
  if ((void *) array == NULL) raise %(bad-arg (owner "Array.postfixindex"));
  int requested = index, length = _int_length(array);
  index = x2c_normalize_index(index, length);
  if (index < 0)
    raise %(bad-arg (owner "Array.postfixindex") (index $requested));
  Var *arr = (Var *) array.bytes;
  return Var.postfix(arr + index, op);
}

/** Appends `elem` to the end of `array` and returns it.
    Returning the appended value lets a push be used directly in another
    expression. The array grows as needed; capacity is an implementation
    detail.

    ```x2c
    ~Array queue = %[];
    queue.push(10);
    queue.push(%"twenty");
    printf("%s\n", queue.repr().str());
    ```
    Raises: `<void-op>` when `elem` is `void`, or `<size-limit>` when the
    `Array` cannot grow within its index domain, or `<alloc-fail>` when storage
    cannot grow. These failures leave `array` unchanged.
*/
Var Array.push(Array array, Var elem) {
  _require_array_value(elem);
  if (array.length >= INT_MAX) {
    size_t size = array.length;
    raise %(size-limit (size $size));
  }
  ((Block) array).append(&elem, 1);
  return elem;
}

/** Takes and returns the last element of `array`, or `void` if it is empty.
    With `Array.push` this makes a stack. Both work at the end of the array,
    move no other elements, and are amortized O(1). Capacity is retained
    after taking the element, so taking and pushing again does not
    reallocate.
*/
Var Array.take_last(Array array) {
  size_t n = array.len();
  if (!n) return void;
  Var *arr = (Var *) array.bytes;
  array.length = n - 1;
  return arr[n - 1];
}

/** Removes and returns the first element of `array`, or `void` if it is
    empty.
    Every remaining element moves down one position, so this is O(n) in the
    length while `Array.take_last` is O(1). Pair `Array.push` with `shift`
    for a FIFO queue and with `Array.take_last` for a stack.
*/
Var Array.shift(Array array) {
  Var elem = void;
  return array._core_shift(&elem) ? elem : void;
}

/** Inserts `elem` at the front of `array` and returns it.
    Existing elements move up one position, so this is O(n); `Array.push` is
    the amortized O(1) end of the array. Returning `elem` lets an unshift
    be used directly in another expression, as `Array.push` does.
    Raises: `<void-op>` when `elem` is `void`, or `<size-limit>` when the
    `Array` cannot grow within its index domain, or `<alloc-fail>` when storage
    cannot grow. These failures leave `array` unchanged.
*/
Var Array.unshift(Array array, Var elem) {
  _require_array_value(elem);
  size_t n = array.len();
  if (n >= INT_MAX) raise %(size-limit (size $n));
  array._core_insert(0, elem);
  return elem;
}

/** Inserts `elem` at `index` and returns it, or `void` when out of range.
    Elements at and after `index` move up one position. An insertion may
    also land past the last element, so the accepted range is one wider than
    for reading. `index` may equal `array.len()`, which appends.

    Negative indices normalize against that wider range, so they do not line
    up with `Array.getindex`. `-1` appends at the end, `-2` inserts before
    the last element, and `-(array.len() + 1)` inserts at the front. Anything
    further out inserts nothing and returns `void`.
    Raises: `<void-op>` when `elem` is `void` and `index` is in range, or
    `<size-limit>` when `array` exceeds the `INT_MAX` index limit that
    `Array.getindex` describes, or `<alloc-fail>` when storage cannot grow.
    These failures leave `array` unchanged.
*/
Var Array.insert(Array array, int index, Var elem) {
  int n = _int_length(array);
  if (index < 0) index += n + 1;
  if (index < 0 || index > n) return void;
  if (n == INT_MAX) raise %(size-limit (size $n));
  _require_array_value(elem);
  array._core_insert(index, elem);
  return elem;
}

/** Removes and returns the element at `index`, or `void` when out of range.
    Elements after `index` move down one position, so this is O(n) unless
    `index` is the last one. Negative indices count from the end as in
    `Array.getindex`, so `-1` removes the last element. `Array.insert` uses
    a different rule. An empty array yields `void`.
    Raises: `<size-limit>` when `array` exceeds the `INT_MAX` index limit that
    `Array.getindex` describes.
*/
Var Array.remove(Array array, int index) {
  _int_length(array);
  Var elem = void;
  return array._core_remove(index, &elem) ? elem : void;
}

/** Returns a new `Array` holding the same elements as `array`.
    The copy is shallow and independent: pushing to one does not affect the
    other, but the two share whatever objects their elements point at.
    Because `Array`s are identity-bearing, plain assignment aliases instead of
    copying, so copy before handing scratch storage to code that may mutate
    it.
    Raises: `<size-limit>` or `<alloc-fail>` when the copy cannot be
    represented or allocated.
*/
Self Array.copy(Self array) {
  _int_length(array);
  return array._core_copy();
}

/** Returns a new `Array` holding the elements `array[start:end:step]`.
    This is what `array[start:end:step]` lowers to; a part omitted from that
    literal form becomes the whole-array default. Negative bounds count from
    the end and a negative `step` walks backwards, normalized the same way
    `List` and `String` slicing normalize them, so the rules match across the
    three types.

    The result is a fresh `Array`, never a view, so later writes to either
    side are invisible to the other. A range that selects nothing yields an
    empty `Array`. Ask for the rest of an array by omitting the bound, as in
    `array[start:]`. A forward `end` above the length is not clamped to it
    and reads one element beyond the last.

    ```x2c
    ~Array digits = %[0, 1, 2, 3, 4, 5];
    printf("%s %s\n", digits[1:4].repr(), digits[3:].repr());
    printf("%s %s\n", digits[::2].repr(), digits[::-1].repr());
    ```
    Raises: `<bad-arg>` when `step` is zero, or `<size-limit>` when `array`
    exceeds the `INT_MAX` index limit that `Array.getindex` describes. */
Self Array.getslice(Self array, int start, int end, int step) {
  if (!step) raise %(bad-arg (owner "Array.getslice") (step $step));
  _int_length(array);
  return array._core_getslice(start, end, step);
}

static void _setslice(Array array, int start, int end, Array values) {
  _int_length(array);
  if (values) _int_length(values);
  array._core_setslice(start, end, values);
}

/** Replaces the region `array[start:end]` with the elements of `values` and
    returns `array`.
    The replacement need not match the length of the region it replaces.
    The array grows or shrinks and the tail moves to fit. A null or empty
    `values` deletes the region, and an empty region inserts.

    Bounds are normalized as slice bounds, and a reversed pair is swapped.
    There is no `step` and no bracket spelling; `array[start:end] = values`
    is not accepted, so call the method. Aliasing is handled, so passing
    `array` as its own `values` copies first.
    Raises: `<size-limit>` when either `Array` cannot be indexed or the result
    cannot be represented, or `<alloc-fail>` while copying an aliased source
    or growing. These failures leave `array` unchanged.
*/
Self Array.setslice(Self array, int start, int end, Self values) {
  _setslice(array, start, end, values);
  return array;
}

/** Removes normalized bounds `[start:end]` and returns a fresh `Array`.
    A reversed pair is swapped. Allocation or size failure occurs before
    `array` is changed.
*/
Self Array.remslice(Self array, int start, int end) {
  _int_length(array);
  return array._core_remslice(start, end);
}

/** Replaces `remove_count` elements at `index` with `values` and returns
    what was removed.
    The returned `Array` is fresh and holds the removed region in order.
    `index` is normalized as a slice bound, so a negative value counts from
    the end and a value past the end clamps to it. A `remove_count` of zero
    or less removes nothing, making `splice` an insertion; a null `values`
    makes it a deletion.
    Raises: `<size-limit>` when either `Array` or the result cannot be
    represented, or `<alloc-fail>` while copying or growing. These failures
    leave `array` unchanged.
*/
Self Array.splice(Self array, int index, int remove_count, Self values) {
  _int_length(array);
  if (values) _int_length(values);
  return array._core_splice(index, remove_count, values);
}

/** Returns the index of the first element equal to `value`, or -1.
    The scan is linear and compares with `Var` equality, the same rule `==`
    applies to boxed values. `Array`s and `Map`s participate
    structurally, while
    `===` remains the identity test. `Array.indexof` is a synonym.
    Raises: `<size-limit>` when `array` exceeds the `INT_MAX` index limit that
    `Array.getindex` describes.
*/
int Array.find(Array array, Var value) {
  _int_length(array);
  return array._core_find(value);
}

/** Returns nonzero when some element of `array` equals `value`.
    Uses the same linear search and structural `Var` equality as `Array.find`.
    Use a `Map` for frequent membership tests.
    Raises: `<size-limit>` when `array` exceeds the `INT_MAX` index limit that
    `Array.getindex` describes.
*/
int Array.contains(Array array, Var value) => array.find(value) != -1;

/** Returns how many elements compare equal to `value`. */
int Array.count(Array array, Var value) {
  _int_length(array);
  return array._core_count(value);
}

/** Returns `Array.find(array, value)`. */
int Array.indexof(Array array, Var value) => array.find(value);

/** Returns a new `Array` holding the elements of `a` followed by those of `b`.
    Neither input is modified and the result is a fresh object. A null or
    empty `b` yields a copy of `a`.
    Raises: `<size-limit>` or `<alloc-fail>` when the result cannot be
    represented or allocated.
*/
Self Array.concat(Self a, Self b) {
  _int_length(a);
  if (b && b.length) {
    if (b.length > INT_MAX - a.length) {
      size_t size = b.length;
      raise %(size-limit (size $size));
    }
  }
  return a._core_concat(b);
}

/** Reverses `array` in place and returns that same `Array`.
    To preserve the original order, slice with a negative step
    (`array[::-1]`), which builds a fresh `Array`.
*/
Self Array.reverse(Self array) => array._core_reverse();

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
  Array output = %[], result = NULL;
  defer if ((void *) result == NULL) output.free();
  foreach (Var item, array) {
    FuncArg arguments[1] = { FuncArg.value(item) };
    output.push(func.apply(1, arguments));
  }
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
  Array output = %[], result = NULL;
  defer if ((void *) result == NULL) output.free();
  size_t an = a.len(), bn = b.len(), n = (an < bn) ? an : bn;
  for (size_t i = 0; i < n; i++) {
    FuncArg arguments[2] = {
      FuncArg.value(a[i]), FuncArg.value(b[i])
    };
    output.push(func.apply(2, arguments));
  }
  return result = output;
}

/** Left-folds a nonempty `Array`, or returns `void` when it is empty.
    Elements are passed as values. An empty or one-element `Array` does not
    invoke or check `func`. Otherwise the callback receives the accumulator
    then each remaining element, runs front to back, and is not retained. It
    must not structurally mutate `array` during the walk. Any cause from
    `Func.apply` or `func` propagates without changing `array` itself.
*/
Var Array.reduce(Array array, Func func) {
  size_t n = array.len();
  if (n == 0) return void;
  Var acc = array[0];
  for (size_t i = 1; i < n; i++) {
    FuncArg arguments[2] = {
      FuncArg.value(acc), FuncArg.value(array[i])
    };
    acc = func.apply(2, arguments);
  }
  return acc;
}

static int _compare_var(Var a, Var b) => a.compare(b);
$array.core.observe(Array, Var, _compare_var);

/** Compares `Array`s lexicographically with `Var.compare`. */
int Array.compare(Array a, Array b) => a._core_compare(b);

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
    ~Array numbers = %[5, 3, 9, 1];
    Array sorted = numbers.sort();
    printf("%s %d\n", numbers.repr(), sorted == numbers);
    ```
    Raises: causes from element comparison. The `Array` may already be
    partially
    reordered when a catch receives the cause. */
Self Array.sort(Self array) {
  if (!array || array.length < 2) return array;
  qsort(array.bytes, array.length, sizeof(Var), _sort_compare);
  return array;
}

static int _sort_order(Func compare, Var left, Var right) {
  FuncArg arguments[2] = { FuncArg.value(left), FuncArg.value(right) };
  return compare.apply(2, arguments).int();
}

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
  Array target = $auto(%[]);
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

struct ArraySortEntry {
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
    FuncArg arguments[1] = { FuncArg.value(value) };
    entries[index].key = key.apply(1, arguments);
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
    ~Array heap = %[];
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
void Array.heap_push(Array heap, Var val) {
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
Var Array.heap_pop(Array heap) {
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
void Array.heapify(Array heap) {
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
String Array.join(Array array, String separator) {
  size_t n = array.length;
  if (n == 0) return "";
  Buffer buf = Buffer.new(0);
  for (size_t i = 0; i < n; i++) {
    Var elem = ((Var *) array.bytes)[i];
    if (elem is <string>) buf.write(elem.string());
    else elem.write_str(buf);
    if (separator && i < n - 1) buf.write(separator);
  }
  String str = buf.str_free();
  return str;
}

/** Returns nonzero when two `Array`s have structurally equal elements. */
int Array.equal(Array a, Array b) => a._core_equal(b);

/** Appends the readable `Array` representation to `out`. */
Buffer Array.write_repr(Array array, Buffer out) =>
  array._core_write(out, <repr>);

/** Appends the `Array` display text to `out`, using each element's
    `write_str`.
    `Array.str` materializes this into a `String`.
*/
Buffer Array.write_str(Array array, Buffer out) =>
  array._core_write(out, <str>);

/** Returns an `Array` display `String` using each element's `str`. */
String Array.str(Array array) {
  Buffer buf = $auto(Buffer.new(0));
  array.write_str(buf);
  return buf.str();
}

/** Returns the readable `[ a, b, c ]` representation of `array`.
    Each element is rendered with its own `repr`, so `String`s appear quoted
    and `Symbol`s in angle brackets. The result is for reading and for
    diagnostics; unlike the `List` reader syntax it does not round-trip back
    through a parser. An empty `Array` renders as `[  ]`.

    `Array.str` has the same shape but uses each element's `str` form.
    `Array.write_repr` and `Array.write_str` append to a `Buffer` instead of
    allocating a `String`, and the two `String` forms are built on them.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
String Array.repr(Array array) {
  Buffer buf = $auto(Buffer.new(0));
  array.write_repr(buf);
  return buf.str();
}

static int _next(Iter iter, Var *out) {
  Array array = iter.obj;
  if (!array) return 0;
  int index = (int) iter.state.integer(), length = _int_length(array);
  if (index >= length) return 0;
  Var *values = (Var *) array.bytes;
  *out = values[index];
  iter.state = index + 1;
  return 1;
}

/** Initializes `dest` as an iterator over the elements of `x`.
    The caller owns the storage: declare a `struct Iter` and pass its
    address. The return value is that same `dest`, or `NULL` when `dest` is
    null, as in every iterator constructor in the library.
    `foreach (Var item, array)` uses this, and the lazy combinators start
    here.

    The iterator borrows `x` and its stored `Var` values, so
    the `Array` and any
    pointed-to values used by the caller must remain live. An `Iter` is
    single-pass, with no rewind, and any structural mutation of
    the `Array` while
    one is outstanding invalidates it. `Iter.array` is the other direction,
    draining an iterator into a fresh `Array`, and `Array.list` converts to a
    canonical `List`.
*/
Iter Array.iter(Array x, Iter dest) {
  if (!dest) return NULL;
  return dest.init(x, _next, 0);
}

/** Drains `iter` into a fresh `Array`. */
Array Iter.array(Iter iter) {
  Array output = %[], result = NULL;
  defer if ((void *) result == NULL) output.free();
  foreach (Var item, iter) output.push(item);
  return result = output;
}

/** Ends the owned lifetime when a managed local leaves its block. */
void Array.cleanup(Array value) { value.free(); }
