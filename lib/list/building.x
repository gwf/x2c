/*  building.x -- List building operations */

// conversion

/** Returns a new `List` holding the elements of `arr` in order.
    Cells are built from the end backwards through `cons`, so the result is
    canonical and shares whatever tail it already has in common with another
    `List`. `arr` is neither consumed nor freed.
    Raises: `<alloc-fail>` while constructing the result.
*/
List Array.list(Array arr) => _prepend_array(arr, NULL);

static List _prepend_array(Array values, List tail) {
  Var *items = values.bytes;
  for (size_t i = values.len(); i; i--) tail = cons(items[i - 1], tail);
  return tail;
}

/** Returns `arr.list()` and frees `arr`.
    The conversion uses `Array.list`, so the result is canonical and may
    share existing cells, including cells owned by an ancestor pool.
    It does not adopt the `Array`'s storage. `arr` is released on success
    and when the conversion transfers an `Error`.
    Raises: `<alloc-fail>` while constructing the result.
*/
List Array.list_free(Array arr) {
  defer arr.free();
  return arr;
}

/** Returns a new `Array` holding the elements of `lst` in order.
    The `Array` is a fresh mutable container the caller owns and should free;
    the elements are shared, since they are only `Var`s. Convert when you need
    indexed access or in-place mutation.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
    The partial result is freed.
*/
Array List.array(List lst) {
  Array output = [], result = NULL;
  defer if (result == NULL) output.free();
  foreach (Var value in lst) output.push(value);
  return result = output;
}

/** Returns the entries of `map` as a `List` of two-element `(key value)`
    `List`s, in the map's iteration order.
    This is the eager form of `Map.enumerate`: the pairs arrive as ordinary
    `List` data instead of through a cursor. An empty `map` returns nil. The
    pair cells are new; the keys and values are shared.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
meta native List Map.list(Map map) {
  Array pairs = [];
  foreach (Var (key, value) in map) pairs.push(%($key $value));
  return pairs.list_free();
}

/** Drains `iter` into a new `List`.
    The iterator is consumed to exhaustion, so this is meaningful once and
    never returns for an infinite source. Elements appear in iteration order.
    Raises: whatever the iterator's source raises, or `<alloc-fail>` while
    constructing the result.
*/
meta native List Iter.list(Iter iter) {
  Array values = auto [];
  foreach (Var item in iter) values.push(item);
  return values;
}

// building

/** Returns the concatenation of `a` and `b`.
    Neither input is modified. `b` becomes the shared tail of the result, so
    only `a`'s cells are rebuilt, O(len(a)) of them. When either side is `nil`
    the other side is returned as it stands.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the copied
    prefix.
*/
Self List.append(Self a, Self b) {
  if (!a) return b;
  if (!b) return a;
  Array values = auto a;
  return _prepend_array(values, b);
}

/** Returns the concatenation of exactly `list_count` `List` arguments.
    Nil is a valid argument, no sentinel is read, and the final nonempty `List`
    becomes the shared tail of the result.
    Raises: `<size-limit>` when `list_count` exceeds the supported index
    range, or `<alloc-fail>` while constructing the result.
*/
List List.concat_n(unsigned list_count, ...) {
  va_list ap;
  va_start(ap, list_count);
  List out = _concat_va(list_count, ap);
  va_end(ap);
  return out;
}

static List _concat_va(unsigned n, va_list ap) {
  if (n > INT_MAX) raise %(size-limit (operation "List.concat_n") (count $n));
  Array lists = auto [];
  for (unsigned i = 0; i < n; i++) lists.push(va_arg(ap, List));
  return _concat_lists(lists);
}

/* Each List is prepended to the concatenation of the ones after it. */
static List _concat_lists(Array lists) {
  List tail = NULL;
  for (int i = (int) lists.len() - 1; i >= 0; i--) {
    List current = lists[i];
    tail = current.append(tail);
  }
  return tail;
}

/** Builds a `List` from exactly `element_count` `Var` arguments.
    Every argument is data, so `void` raises instead of being read as a
    terminator. A zero count returns `nil`.
    Raises: `<void-op>` when an argument is `void`, or `<alloc-fail>` or
    `<size-limit>` while constructing the result.
*/
List List.list_n(unsigned element_count, ...) {
  va_list ap;
  va_start(ap, element_count);
  List out = _list_va(element_count, ap);
  va_end(ap);
  return out;
}

static List _list_va(unsigned n, va_list ap) {
  Array values = auto [];
  for (unsigned i = 0; i < n; i++) {
    Var value = va_arg(ap, Var);
    if (value is void) raise %(void-op (operation "List.list_n") (index $i));
    values.push(value);
  }
  return values;
}

/** Returns a new `List` holding the elements of `lst` in reverse order.
    Fresh cells are built through `cons`, so the result is canonical and `lst`
    is untouched. Reversing `nil` gives `nil`.
    Raises: `<alloc-fail>` while constructing the result.
*/
Self List.reverse(Self lst) {
  List rev = NULL;
  foreach (Var value in lst) rev = cons(value, rev);
  return rev;
}
