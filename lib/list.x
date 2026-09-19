/*  list.x -- linked list with `Var` elements

    Copyright (c) 2025 Gary William Flake

    `List` is an immutable, interned cons chain. A car may hold any non-`void`
    `Var`;
    a cdr is `nil` or another `List`. Canonical identity is the car's exact
    `Var`
    bits plus the canonical tail identity, so mutating an `Array` or `Map`
    stored
    in a car does not change the identity of the cell that contains it.

    Construction searches the requested pool and its ancestors. An existing
    cell keeps its ancestor's lifetime; a miss belongs to the requested pool.
    Releasing a nested pool invalidates its unpromoted cells, while promotion
    preserves complete canonical `List`, `String`, and long-`Atom` structure
    without
    changing pointers. `void` is a terminal sentinel, not `List` data.
*/

#pragma once

$(import "error-macros.xmacro")
#include "common.x"
#include "var.x"

/** Names an immutable canonical cons cell, or `nil` as NULL.
    A nonnull cell is borrowed from the pool that owns its exact car and tail
    identity; callers neither mutate nor free it. The car is never `void`, and
    the tail is `nil` or another live canonical `List`.
*/
typedef struct List {
  Var car;
  struct List *cdr;
} *List;

/* Builds a canonical cell in the given pool without changing the process-wide
   active List pool. Error uses this to keep diagnostic values out of
   application pool brackets. */
/** Returns the canonical cell for `head` and `tail` in `pool`'s chain.
    An ancestor hit keeps that ancestor's ownership; a miss is owned by `pool`.
    A null pool or `void` head returns `nil` without allocating. Any
    pool-managed
    graph reachable through `head` or `tail` is borrowed and must remain live
    for at least as long as the result.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while installing a
    new cell.
*/
List List.cons_in(Pool pool, Var head, List tail) {
  if (!pool || head is void) return NULL;
  /* Compiler construction is canonical-hit-heavy. One stack-query probe of
     the whole chain answers a hit without allocating and leaves the miss
     path the innermost insert alone. */
  struct List query = { head, tail };
  Var existing = pool.lookup((List) &query);
  if (existing is not void) return existing;
  List cell = pool.malloc(sizeof(struct List));
  cell.car = head;
  cell.cdr = tail;
  return pool.intern_new(cell, cell);
}

#pragma private

#include "symbol.x"
#include "atom.x"
#include "block.x"
#include "buffer.x"
#include "exception.x"
#include "func.x"
#include "map.x"
#include "scope.x"
#include "pool.x"
#include "string.x"
#include "iter.x"
#include "array.x"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <limits.h>

/* In an ordinary shared-pool List.cons graph, an ancestor-owned cell can only
   reference ancestor-owned cars and tails, so the walk stops at the first
   cell the innermost pool does not own. List.cons_in callers can create
   cross-pool graphs and must preserve those borrowed lifetimes themselves.
   String cars and long Atom payloads promote through the String pool chain;
   other Var kinds are Scope-managed and out of pool jurisdiction. */
static void _promote_node(Var node) {
  if (node is <string>) {
    String.promote(node);
    return;
  }
  if (node is <lsym>) {
    Atom.promote(node);
    return;
  }
  if (node is not <list>) return;
  for (List cur = node; cur; cur = cur.cdr) {
    if (!Pool.current().promote(cur, cur)) break;
    _promote_node(cur.car);
  }
}

/** Moves `lst` out of the innermost interning pool into its parent.
    Cells, nested `List`s, interned `String` cars, and long `Atom` payloads
    all move together, so a promoted `List` keeps its complete identity graph
    across the matching `Pool.close`. Pointers never change and ancestor-owned
    structure is left where it is; the return value is `lst` itself.

    Cells are immutable, so an ancestor-owned cell can only reference
    ancestor-owned cars and tails. The walk stops at the first cell the
    innermost pool does not own. Promoting an already-promoted `List` is
    therefore cheap. `Var` kinds other than `String`, `Atom`, and `List` are
    `Scope`-managed and outside pool jurisdiction.

    A null `lst` returns itself unchanged.
*/
Self List.promote(Self lst) {
  if (!lst) return lst;
  _promote_node(lst);
  return lst;
}

static int _try_own_node(Var node) {
  if (node is <string>) return node.string().try_own();
  if (node is <lsym>) return node.str().try_own();
  if (node is not <list>) return 1;
  for (List cur = node; cur; cur = cur.cdr) {
    if (!Pool.current().own(cur, cur)) return 0;
    if (!_try_own_node(cur.car)) return 0;
  }
  return 1;
}

/** Proves `lst` and its canonical children safe beyond every active pool.
    Returns 1 when the complete value is `nil`, already permanent, or can be
    promoted to the outermost `List` and `String` pools. Returns 0 when an
    active
    pool does not own part of the value. A zero result may follow successful
    promotion of an earlier cell or child.
    Raises: `<alloc-fail>` when promotion metadata cannot be allocated.
*/
int List.try_own(List lst) => !lst || _try_own_node(lst);

/** Returns the canonical cons cell for `head` and `tail`.
    Repeating the call with the same head bits and canonical tail returns the
    same cell from the active pool chain. An ancestor hit remains owned there;
    a miss belongs to the active pool. The tail is shared, and `nil` is the
    null
    pointer.
    Raises: `<void-op>` when `head` is `void`, or `<alloc-fail>`,
    `<size-limit>`, or `<invariant>` when a new canonical cell cannot be
    installed.
*/
List cons(Var head, List tail) {
  if (head is void) raise %(void-op (owner "List.cons"));
  return List.cons_in(Pool.current(), head, tail);
}

static int _is_active_canonical(List list) =>
  Pool.current().lookup(list) === list;

/** Method form of `cons`, with the same identity, lifetime, and failures. */
List List.cons(Var head, List tail) => cons(head, tail);
/** Returns `cons(head, tail)`, with the same identity and failures. */
List Var.cons(Var head, List tail)  => cons(head, tail);

/** Returns the head of `x`, or `void` when `x` is `nil`. */
inline Var  car(List x)  => x ? x.car : void;

/** Returns the tail of `x`, or `nil` when `x` is `nil`.
    Nil-safe like `car`. The tail is the same canonical structure the cell was
    built from.
*/
inline List cdr(List x)  => x ? x.cdr : NULL;

/** Method form of `car`: the head of `lst`, or `void` when `lst` is `nil`. */
inline Var  List.car(List lst)     => car(lst);
/** Method form of `cdr`: the tail of `lst`, or `nil` when `lst` is `nil`. */
inline Self List.cdr(Self lst)     => cdr(lst);
/** Returns `car(car(lst))`.
    Compound accessors read from right to left: `a` applies `car` and `d`
    applies `cdr`. Every step is `nil`-safe.
*/
inline Var  List.caar(List lst)    => car(car(lst));
/** Returns `car(cdr(lst))`, or `void` when there is no second element. */
inline Var  List.cadr(List lst)    => car(cdr(lst));
/** Returns the tail after two cells, or `nil`. */
inline Self List.cddr(Self lst)    => cdr(cdr(lst));
/** Returns the third element, or `void`. */
inline Var  List.caddr(List lst)   => car(cdr(cdr(lst)));

/** Treats `var` as a `List` and returns its first element. */
Var  Var.car(Var var)              => car(var.pointer());
/** Treats `var` as a `List` and returns its tail. */
List Var.cdr(Var var)              => cdr(var.pointer());
/** Applies the `caar` selector chain to `Var`. */
inline Var  Var.caar(Var var)      => car(car(var));
/** Applies the `cadr` selector chain to `Var`. */
inline Var  Var.cadr(Var var)      => car(cdr(var));
/** Applies the `cddr` selector chain to `Var`. */
inline List Var.cddr(Var var)      => cdr(cdr(var));
/** Applies the `caddr` selector chain to `Var`. */
inline Var  Var.caddr(Var var)     => car(cdr(cdr(var)));

static List _prepend_array(Array values, List tail) {
  Var *data = values.bytes;
  for (size_t i = values.len(); i; i--) {
    tail = cons(data[i - 1], tail);
  }
  return tail;
}

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
  Array values = $auto([]);
  foreach (Var value, a) values.push(value);
  return _prepend_array(values, b);
}

static List _concat_lists(Array lists) {
  List result = NULL;
  for (int i = (int) lists.len() - 1; i >= 0; i--) {
    List current = lists[i];
    result = current.append(result);
  }
  return result;
}

static List _concat_n_va(unsigned list_count, va_list ap) {
  if (list_count > INT_MAX)
    raise %(size-limit (owner "List.concat_n") (count $list_count));
  Array lists = $auto([]);
  for (unsigned i = 0; i < list_count; i++)
    lists.push(va_arg(ap, List));
  return _concat_lists(lists);
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
  List result = _concat_n_va(list_count, ap);
  va_end(ap);
  return result;
}

static List _n_va(unsigned element_count, va_list ap) {
  Array values = $auto([]);
  for (unsigned i = 0; i < element_count; i++) {
    Var value = va_arg(ap, Var);
    if (value is void) raise %(void-op (owner "List.list_n") (index $i));
    values.push(value);
  }
  return values;
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
  List result = _n_va(element_count, ap);
  va_end(ap);
  return result;
}

/** Returns a new `List` holding the elements of `lst` in reverse order.
    Fresh cells are built through `cons`, so the result is canonical and `lst`
    is untouched. Reversing `nil` gives `nil`.
    Raises: `<alloc-fail>` while constructing the result.
*/
Self List.reverse(Self lst) {
  List rev = NULL;
  foreach (Var value, lst) {
    rev = cons(value, rev);
  }
  return rev;
}

/** Returns the last value in `lst`, or `void` when it is empty. */
Var List.last(List lst) {
  if (!lst) return void;
  List tail;
  while ((tail = lst.cdr())) lst = tail;
  return lst.car();
}

/** Returns the first index of `key`, or -1 when absent. */
int List.index(List l, Var key) {
  for (int index = 0; l; l = l.cdr(), index++) if (l.car == key) return index;
  return -1;
}

/** Reports whether `lst` contains `key` by `Var` equality. */
int List.contains(List lst, Var key) => lst.index(key) != -1;

/** Returns the number of cells in `lst` in O(n) time. */
int List.len(List lst) {
  int len = 0;
  for (List l = lst; l; l = l.cdr()) len++;
  return len;
}

/** Returns a canonical `List` holding `fn` applied front to back.
    Elements are passed as values, and mapping `nil` gives `nil` without
    invoking
    or checking `fn`. A null `fn` on nonempty input raises `<bad-arg>`, and a
    callback result of `void` raises `<void-op>` when the result `List` is
    built.
    Raises: those causes, whatever `Func.apply` or `fn` raises, or
    `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
List List.map(List lst, Func fn) {
  if (!lst) return NULL;
  Array values = $auto([]);
  foreach (Var value, lst) {
    FuncArg arguments[1] = { FuncArg.value(value) };
    values.push(fn.apply(1, arguments));
  }
  return values;
}

/** Folds `fn` over the elements of `lst` from the left, starting at `seed`.
    `fn` receives the accumulator and then the next element, and returns the
    next accumulator. A `void` seed means "no seed": the first element becomes
    the initial accumulator and the fold starts at the second, and folding
    `nil`
    that way returns `void`. A null `fn` returns the accumulator untouched,
    which for a `void` seed is the head.

    Any cause raised by `fn` propagates.
*/
Var List.foldl(List lst, Var seed, Func fn) {
  Var acc = seed;
  List cur = lst;
  if (acc is void) {
    if (!cur) return void;
    acc = cur.car;
    cur = cur.cdr();
  }
  if (!fn) return acc;
  foreach (Var value, cur) {
    FuncArg arguments[2] = {
      FuncArg.value(acc), FuncArg.value(value)
    };
    acc = fn.apply(2, arguments);
  }
  return acc;
}

/** Returns the first element `pred` accepts by ordinary `Var` truthiness, or
    `void`.

    Any cause raised by `pred` or its result's truth operation propagates. A
    null `pred` returns `void`.
*/
Var List.find(List lst, Func pred) {
  if (!pred) return void;
  foreach (Var value, lst) {
    FuncArg arguments[1] = { FuncArg.value(value) };
    if (pred.apply(1, arguments)) return value;
  }
  return void;
}

/** True when at least one element satisfies `pred` by ordinary `Var`
    truthiness.
    Stops at the first accepted element. Nil and a null `pred` are false.

    Any cause raised by `pred` or its result's truth operation propagates.
*/
int List.any(List lst, Func pred) {
  if (!pred) return 0;
  foreach (Var value, lst) {
    FuncArg arguments[1] = { FuncArg.value(value) };
    if (pred.apply(1, arguments)) return 1;
  }
  return 0;
}

/** True when every element satisfies `pred` by ordinary `Var` truthiness.
    Stops at the first rejection. Nil is true; a null `pred` is false for a
    nonempty `List`.

    Any cause raised by `pred` or its result's truth operation propagates.
*/
int List.all(List lst, Func pred) {
  if (!lst) return 1;
  if (!pred) return 0;
  foreach (Var value, lst) {
    FuncArg arguments[1] = { FuncArg.value(value) };
    if (!pred.apply(1, arguments)) return 0;
  }
  return 1;
}

/** Returns a copy of `lst` ordered by `Var.compare`.
    `lst` is unchanged. There is no comparator parameter. `Var.compare` orders
    the element tags involved, so a mixed-kind `List` still sorts. A `List` of
    fewer than two cells is returned as it stands.
    Raises: whatever element comparison raises, or `<alloc-fail>` while
    constructing the result.
*/
Self List.sort(Self lst) {
  if (!lst || !lst.cdr()) return lst;
  Array values = $auto([]);
  foreach (Var value, lst) values.push(value);
  values.sort();
  return values;
}

/** Returns a stable sorted copy using `Array.sort_with`'s callback contract.
    The input List is unchanged. Fewer than two cells return unchanged without
    a callback. Raises: allocation and the comparator's ordinary causes.
*/
Self List.sort_with(Self lst, Func compare) {
  if (!lst || !lst.cdr()) return lst;
  Array values = $auto([]);
  foreach (Var value, lst) values.push(value);
  values.sort_with(compare);
  return values;
}

/** Returns a stable sorted copy using `Array.sort_by`'s callback contract.
    The key runs once per element in input order; an empty List invokes none.
    The input List is unchanged. Raises: allocation and the key's ordinary
    causes, including failure to compare the resulting keys.
*/
Self List.sort_by(Self lst, Func key) {
  if (!lst) return lst;
  Array values = $auto([]);
  foreach (Var value, lst) values.push(value);
  values.sort_by(key);
  return values;
}

/** Returns a new `List` holding the elements of `arr` in order.
    Cells are built from the end backwards through `cons`, so the result is
    canonical and shares whatever tail it already has in common with another
    `List`. `arr` is neither consumed nor freed.
    Raises: `<alloc-fail>` while constructing the result.
*/
List Array.list(Array arr) => _prepend_array(arr, NULL);

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

/** Returns the entries of `map` as a `List` of two-element `(key value)`
    `List`s, in the map's iteration order.
    This is the eager form of `Map.enumerate`, for a caller that wants the
    pairs as ordinary `List` data rather than a cursor. An empty `map`
    returns nil. The pair cells are new; the keys and values are shared.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
List Map.list(Map map) {
  Array pairs = [];
  foreach (Var (key, value), map) pairs.push(%($key $value));
  return pairs.list_free();
}

/** Returns a new `Array` holding the elements of `lst` in order.
    The `Array` is a fresh mutable container the caller owns and
    should free; the
    elements are shared, since they are only `Var`s. Convert when you need
    indexed access or in-place mutation.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
Array List.array(List lst) {
  Array array = [];
  foreach (Var value, lst) array.push(value);
  return array;
}

/** Returns a copy of `lst` with later duplicates removed.
    The first occurrence of each value is kept and the original order is
    preserved. Duplicate detection runs through `Iter.unique`, whose state is
    held inside a `Scope` bracket that is released before
    returning. A `List` of
    fewer than two cells is returned as it stands.
    Raises: causes from `Map` hashing or equality, or `<alloc-fail>` or
    `<size-limit>` while constructing the result.
*/
Self List.unique(Self lst) {
  if (!lst || !lst.cdr()) return lst;
  $scope() {
    struct Iter iter_storage, unique_storage;
    Iter iter = lst.iter(&iter_storage);
    Iter unique = iter.unique(&unique_storage);
    return unique;
  }
}

/** Combines aligned values from two `List`s with `fn`.
    A null `fn` produces two-element pair `List`s. The shorter input determines
    the result length, and an empty input does not inspect the callback. A
    callback receives the left and right values and is invoked front to back.
    Raises: whatever `Func.apply`, `fn`, or result canonicalization raises.
*/
List List.zip_with(List a, List b, Func fn) {
  Array values = $auto([]);
  for (; a && b; a = a.cdr(), b = b.cdr()) {
    Var left = a.car, right = b.car, item;
    if (fn) {
      FuncArg arguments[2] = {
        FuncArg.value(left), FuncArg.value(right)
      };
      item = fn.apply(2, arguments);
    }
    else item = %($left $right);
    values.push(item);
  }
  return values;
}

/** Maps `fn` over aligned pairs from `a` and `b`.
    A null callback returns `nil` without examining either `List`; otherwise
    this
    has the length, order, ownership, and failures of `List.zip_with`.
*/
List List.map2(List a, List b, Func fn) {
  if (!fn) return NULL;
  return a.zip_with(b, fn);
}

static Var _sublis_node(List alist, Var node) {
  if (node is not <list>) {
    Var replacement = alist.assoc(node);
    return replacement is void ? node : replacement;
  }
  List list = node;
  if (!list) return list;
  Array items = $auto([]);
  foreach (Var source, list) items.push(_sublis_node(alist, source));
  return items.list();
}

/** Recursively substitutes non-`List` nodes in `tree` from `alist`.
    Each association is a `List` whose first value is the key and whose second
    value is the replacement. Unmatched leaves are shared; `List` structure is
    rebuilt canonically, and `nil` returns `nil`.
    Raises: a cause from key equality, or `<alloc-fail>` or `<size-limit>`
    while constructing the result.
*/
List List.sublis(List alist, List tree) {
  if (!tree) return NULL;
  return _sublis_node(alist, tree);
}

/** Flattens one level of nested `List`s into a canonical result.
    A nested `nil` contributes no element, non-`List` values retain their
    identity,
    and `nil` returns `nil`.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
Self List.flatten(Self lst) {
  if (!lst) return lst;
  Array values = $auto([]);
  foreach (Var head, lst) {
    if (head is <list>) {
      List inner = head;
      foreach (Var item, inner) values.push(item);
    }
    else values.push(head);
  }
  return values;
}

static void _flatten_all_collect(Array values, List lst) {
  foreach (Var head, lst) {
    if (head is <list>) _flatten_all_collect(values, head);
    else values.push(head);
  }
}

/** Recursively flattens every nested `List` into a canonical result.
    Nested `nil` contributes no element and `nil` returns `nil`.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
Self List.flatten_all(Self lst) {
  if (!lst) return lst;
  Array values = $auto([]);
  _flatten_all_collect(values, lst);
  return values;
}

/** Returns the shared tail beginning `n` cells in.
    Returns `nil` past the end and `list` itself when `n` is nonpositive.
*/
Self List.nth_cdr(Self list, int n) {
  while (n-- > 0 && list) list = list.cdr();
  return list;
}

/** Returns `list[index]`, or `void` when out of range.
    A negative index counts from the end and is found without a length pass.
*/
Var List.getindex(List list, int index) {
  if (index < 0) {
    unsigned distance = (unsigned) -(long) index;
    List lead = list;
    while (distance--) {
      if (!lead) return void;
      lead = lead.cdr();
    }
    List lag = list;
    while (lead) {
      lead = lead.cdr();
      lag = lag.cdr();
    }
    return lag ? lag.car : void;
  }
  List nth = list.nth_cdr(index);
  return nth ? nth.car : void;
}

/** Returns the second value of the first association whose key equals `key`.
    Nil entries are skipped. A missing association and a missing second value
    both return `void`, so the two cases look the same here.
*/
Var List.assoc(List list, Var key) {
  foreach (List pair, list) {
    if (!pair) continue;
    Var (pair_key, value) = pair;
    if (pair_key == key) return value;
  }
  return void;
}

/** Looks up an integer index or association key in `list`.
    Integer keys use `List.getindex`, including negative indexes; every other
    key uses `List.assoc`. Either absent form returns `void`, as does an
    integer key outside the `int` index domain, which no `List` can reach.
*/
Var List.get(List list, Var key) {
  if (key.kind() != <integer>) return list.assoc(key);
  /* Narrowing the key instead would fold an unreachable index onto a real
     one, so 2^32 would answer with the first element. */
  long long index = key.long_long();
  if (index != (int) index) return void;
  return list[(int) index];
}

/** Returns the last `count` elements of `list`.
    The result is an existing tail of `list`, so nothing is allocated. When
    `count` reaches or exceeds the length, the whole `list` comes back.
*/
Self List.tail(Self list, unsigned count) {
  List lead = list;
  for (unsigned i = 0; i < count; i++) {
    if (!lead) return list;
    lead = lead.cdr();
  }
  List lag = list;
  while (lead) {
    lead = lead.cdr();
    lag = lag.cdr();
  }
  return lag;
}

/** Returns the first `count` elements of `list`.
    When `count` reaches or exceeds the length, `list` itself comes back, the
    same pointer. `List`s are immutable, so sharing it is safe. Otherwise fresh
    canonical cells are built for the prefix.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing that prefix.
*/
Self List.head(Self list, unsigned count) {
  List original = list, Array values = $auto([]);
  while (list && count--) {
    values.push(list.car);
    list = list.cdr();
  }
  if (!list) return original;
  return values;
}

static List _collect_subseq(List list, int start, int step, int span) {
  if (span <= 0) return NULL;
  for (int i = 0; list && i < start; i++) list = list.cdr();
  Array values = $auto([]);
  while (list && span--) {
    values.push(list.car);
    for (int i = 0; list && i < step; i++) list = list.cdr();
  }
  return values;
}

/** Returns every `step`th element from `start` up to exclusive `stop`.
    Negative bounds count from the end. `step` must be positive.
    Raises: `<bad-arg>` when `step` is less than 1, or `<alloc-fail>` while
    constructing the result.
*/
Self List.subseq(Self list, int start, int stop, int step) {
  if (step < 1) raise %(bad-arg (owner "List.subseq") (step $step));
  int span = x2c_normalize_slice(&start, &stop, step, list.len());
  return _collect_subseq(list, start, step, span);
}

/** Returns `list[start:stop:step]`.
    `stop` is exclusive, negative bounds count from the end, and a negative
    `step` walks backwards. A full forward slice preserves `list` only when its
    identity is canonical in the active pool chain; otherwise it rebuilds the
    cells there so a detached pool cannot escape through the shortcut.
    Raises: `<bad-arg>` when `step` is zero, or `<alloc-fail>` or
    `<size-limit>` while constructing the result.
*/
Self List.getslice(Self list, int start, int stop, int step) {
  if (!step) raise %(bad-arg (owner "List.getslice") (step $step));
  int len = list.len(), span = x2c_normalize_slice(&start, &stop, step, len);
  if (step == 1 && start == 0 && span == len &&
      (!list || _is_active_canonical(list))) return list;
  if (step > 0) return _collect_subseq(list, start, step, span);
  if (span <= 0) return NULL;
  Array source = $auto(list);
  Array values = $auto([]);
  for (int i = 0; i < span; i++)
    values.push(source[start + i * step]);
  return values;
}

static int _unpack_n_va(
  List src, unsigned destination_count, va_list ap, int list_outputs) {
  if (destination_count > INT_MAX)
    raise %(size-limit (owner "List.unpack_n")
          (count $destination_count));
  int count = 0;
  while (src && count < destination_count) {
    if (list_outputs) {
      List *dst = va_arg(ap, List *);
      if (dst) *dst = src.car();
    }
    else {
      Var *dst = va_arg(ap, Var *);
      if (dst) *dst = src.car();
    }
    src = src.cdr();
    count++;
  }
  return count;
}

/** Writes at most `destination_count` elements through `List` pointers.
    Returns the number written. Extra source cells are left unread, and a
    short source leaves remaining destinations untouched. Each source value is
    decoded as a `List`, so another tag writes `nil`; a null destination is
    skipped
    but still counted.
    Raises: `<size-limit>` when `destination_count` exceeds `INT_MAX`. The
    failure occurs before any destination is written.
*/
int List.unpack_n(List src, unsigned destination_count, ...) {
  va_list ap;
  va_start(ap, destination_count);
  int count = _unpack_n_va(src, destination_count, ap, 1);
  va_end(ap);
  return count;
}

/** Writes at most `destination_count` elements through `Var` pointers.
    Returns the number written. Extra source cells are left unread, and a
    short source leaves remaining destinations untouched. A null destination
    is skipped but still counted.
    Raises: `<size-limit>` when `destination_count` exceeds `INT_MAX`. The
    failure occurs before any destination is written.
*/
int List.unpack_vars_n(List src, unsigned destination_count, ...) {
  va_list ap;
  va_start(ap, destination_count);
  int count = _unpack_n_va(src, destination_count, ap, 0);
  va_end(ap);
  return count;
}

// object methods

/** Returns the stable hash of `List`'s exact head bits and tail identity.
    This is a constant-time hash of one cell, which canonical cells make
    sound. It reaches an element's content only when the `Var` word holds it:
    a small number, a `Symbol`, an `Atom`, a canonical `String`, or a nested
    `List`. An element the word points at hashes by identity, so a wide
    number boxed in a `Scope`, an `Array`, or a `Map` gives two equal-looking
    `List`s two hashes. Mutating an object referenced by the head does not
    change this hash.
*/
unsigned List.hash(List lst) {
  if (!lst) return 0;
  uint64_t h = (uint64_t)(uintptr_t) lst.cdr;
  h ^= lst.car.u64 + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
  h *= 0xd6e8feb86659fd93ULL;
  unsigned result = (unsigned)(h ^ (h >> 32));
  return result ? result : -1;
}

/** Reports equality of canonical chains by exact head and tail identity.
    It matches `List.hash`, so the same elements decide it: content for a
    small number, `Symbol`, `Atom`, canonical `String`, or nested `List`, and
    identity for a wide number boxed in a `Scope`, an `Array`, or a `Map`.
    Two `List`s built from one `long` value hold two boxes and are unequal,
    while `List.compare` reads the values and calls them equal. Use
    `List.compare` where content has to decide.
*/
int List.equal(List a, List b) {
  if ((void *) a == (void *) b) return 1;
  if (!a || !b) return 0;
  return a.car === b.car && a.cdr == b.cdr;
}

/** Compares `a` and `b` lexicographically through `Var.compare`.
    Element comparison causes propagate.
*/
int List.compare(List a, List b) {
  if ((void *) a == (void *) b) return 0;
  while (a && b) {
    int c = a.car().compare(b.car());
    if (c) return c;
    a = a.cdr();
    b = b.cdr();
  }
  if (a == b) return 0;
  return a ? 1 : -1;
}

static void _serialize_list_line(Var elem, Buffer buf, Symbol mode) {
  if (elem is not <list>) {
    if (mode == <str>) elem.write_str(buf);
    else if (elem is <symbol>) Atom.write_repr(elem, buf);
    else elem.write_repr(buf);
    return;
  }
  List lst = elem;
  if (!lst) return (void) buf.write("()");
  RenderPath path;
  if (!path.enter(lst)) return (void) elem.write_pointer_repr(buf);
  defer path.leave();
  buf.write("(");
  if (lst.car() is not <list>) buf.pad();
  buf.push();
  for (List l = lst; l; l = l.cdr()) {
    _serialize_list_line(l.car(), buf, mode);
    if (l.cdr()) buf.write(" ");
  }
  if (buf.get(-1) != ')') buf.pad();
  buf.write(")");
  buf.pop();
}

static void _serialize_nested_list(Var elem, Buffer buf, Symbol mode) {
  const int maxwidth = 80;
  if (buf.pos >= maxwidth - 1) buf.newline_indent();
  else if (buf.pos - buf._indent > 40) buf.newline_indent();
  if (elem is not <list>) {
    size_t before = buf.content.length, position = buf.pos;
    _serialize_list_line(elem, buf, mode);
    size_t length = buf.content.length - before;
    if (position + length > maxwidth) {
      buf.unwrite(length);
      buf.newline_indent();
      _serialize_list_line(elem, buf, mode);
    }
    return;
  }
  List lst = elem;
  if (!lst) {
    if (buf.pos + 2 > maxwidth) buf.newline_indent();
    buf.write("()");
    return;
  }
  {
    Buffer line = $auto(Buffer.new(buf.padding));
    _serialize_list_line(lst, line, mode);
    if (buf.pos + line.content.length <= maxwidth) {
      buf.write_len(line.content.bytes, line.content.length);
      return;
    }
  }
  RenderPath path;
  if (!path.enter(lst)) return (void) elem.write_pointer_repr(buf);
  defer path.leave();
  if (buf.pos - buf.tabstop() > 5) buf.newline_indent();
  buf.write("(");
  if (lst.car() is not <list>) buf.pad();
  buf.push();
  for (List l = lst; l; l = l.cdr()) {
    _serialize_nested_list(l.car(), buf, mode);
    if (l.cdr()) buf.write(" ");
  }
  if (buf.get(-1) != ')') buf.pad();
  buf.write(")");
  buf.pop();
}

/** Returns the human-readable rendering of `lst`.
    Elements are rendered with their own `str`, so a `String` element appears
    unquoted. The writer pads inside parentheses and breaks nested structure
    across lines at about 80 columns. Nil renders as `()`. The canonical
    result follows the active `String` pool chain, may already be owned by an
    ancestor, and remains live until its owning pool is released. Use
    `List.repr` when the text has to read back in.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
String List.str(List lst) {
  Buffer buf = $auto(Buffer.new(0));
  lst.write_str(buf);
  return buf;
}

/** Appends the `List` display text to `out`, using each element's `write_str`.
    `List.str` calls this to build its result. The display form has one space
    inside each parenthesis, as in `( a b )`, including when nested in another
    container. This method temporarily sets the destination `Buffer`'s padding
    to one and restores it afterward.
*/
Buffer List.write_str(List lst, Buffer out) {
  $let(out.padding, 1) {
    _serialize_nested_list(lst, out, <str>);
  }
  return out;
}

/** Returns the re-readable rendering of `lst`.
    This is the `%(...)` spelling of the same data. Elements are rendered with
    their own `repr`, so `String`s come back quoted and `Atom`s print as bare
    names, and `nil` renders as `()`. Long nested structure wraps at about 80
    columns. The canonical result follows the active `String` pool chain, may
    already be owned by an ancestor, and remains live until that owner is
    released.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
String List.repr(List lst) {
  Buffer buf = $auto(Buffer.new(0));
  lst.write_repr(buf);
  return buf;
}

/** Appends the readable representation of `List` to a `Buffer`. */
Buffer List.write_repr(List lst, Buffer out) {
  _serialize_nested_list(lst, out, <repr>);
  return out;
}

static int _next(Iter iter, Var *out) {
  List lst = iter.state;
  if (!lst) return 0;
  *out = lst.car();
  lst = lst.cdr;
  iter.state = lst;
  return 1;
}

/** Writes the next element, advances `cursor`, and returns one.
    Initialize the caller-owned cursor to `lst`. A null pointer or an
    exhausted cursor returns zero without changing `cursor` or `out`. The
    cells are immutable, so only releasing the owning pool invalidates a
    cursor.

    `foreach (Var item, lst)` compiles to this loop.
*/
int List.try_next(List lst, List *cursor, Var *out) {
  if (!cursor || !out || !*cursor) return 0;
  *out = (*cursor).car();
  *cursor = (*cursor).cdr;
  return 1;
}

/** Initializes caller-owned `dest` as a forward iterator over `lst`.
    The iterator borrows the immutable cells and yields their stored `Var` bits
    without retaining them, so the owning pool must outlive iteration. A null
    `dest` returns NULL; `nil` produces an exhausted iterator.
*/
Iter List.iter(List lst, Iter dest) {
  if (!dest) return NULL;
  return dest.init(lst, _next, lst);
}

/** Drains `iter` into a new `List`.
    The iterator is consumed to exhaustion, so this is meaningful once and
    never returns for an infinite source. Elements appear in iteration order.
    Raises: whatever the iterator's source raises, or `<alloc-fail>` while
    constructing the result.
*/
List Iter.list(Iter iter) {
  Array values = $auto([]);
  foreach (Var item, iter) values.push(item);
  return values;
}

/** Returns the elements `pred` accepts by ordinary `Var` truthiness.
    Elements are passed as values, and filtering `nil` gives `nil` without
    invoking or checking `pred`.
    Raises: whatever `Func.apply`, `pred`, or result truthiness raises, or
    `<alloc-fail>` or `<size-limit>` while constructing the result. A null
    `pred` on nonempty input raises `<bad-arg>` from `Func.apply`.
*/
Self List.filter(Self lst, Func pred) {
  if (!lst) return NULL;
  Array values = $auto([]);
  foreach (Var value, lst) {
    FuncArg arguments[1] = { FuncArg.value(value) };
    if (pred.apply(1, arguments)) values.push(value);
  }
  return values;
}
