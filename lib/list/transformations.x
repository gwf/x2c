/*  transformations.x -- List transformations operations */

// callbacks

/** Returns a canonical `List` holding `fn` applied front to back.
    Elements are passed as values, and mapping `nil` gives `nil` without
    invoking or checking `fn`. A null `fn` on nonempty input raises
    `<bad-arg>`, and a callback result of `void` raises `<void-op>` when the
    result `List` is built.
    Raises: those causes, whatever `Func.apply` or `fn` raises, or
    `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
List List.map(List lst, Func fn) {
  if (!lst) return NULL;
  Array values = $auto([]);
  foreach (Var value, lst) values.push(fn.apply_value(value));
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
  foreach (Var value, lst) if (pred.apply_value(value)) values.push(value);
  return values;
}

/** Folds `fn` over the elements of `lst` from the left, starting at `seed`.
    `fn` receives the accumulator and then the next element, and returns the
    next accumulator. A `void` seed means "no seed": the first element becomes
    the initial accumulator and the fold starts at the second, and folding
    `nil` that way returns `void`. A null `fn` returns the accumulator
    untouched, which for a `void` seed is the head.

    Any cause raised by `fn` propagates.
*/
Var List.foldl(List lst, Var seed, Func fn) {
  if (!fn) return seed is void && lst ? lst.car : seed;
  struct Iter storage;
  return lst.iter(&storage).foldl(seed, fn);
}

/** Returns the first element `pred` accepts by ordinary `Var` truthiness, or
    `void`.

    Any cause raised by `pred` or its result's truth operation propagates. A
    null `pred` returns `void`.
*/
Var List.find(List lst, Func pred) {
  struct Iter storage;
  return lst.iter(&storage).find(pred);
}

/** True when at least one element satisfies `pred` by ordinary `Var`
    truthiness. Stops at the first accepted element. Nil and a null `pred` are
    false.

    Any cause raised by `pred` or its result's truth operation propagates.
*/
int List.any(List lst, Func pred) {
  struct Iter storage;
  return lst.iter(&storage).any(pred);
}

/** True when every element satisfies `pred` by ordinary `Var` truthiness.
    Stops at the first rejection. Nil is true; a null `pred` is false for a
    nonempty `List`.

    Any cause raised by `pred` or its result's truth operation propagates.
*/
int List.all(List lst, Func pred) {
  struct Iter storage;
  return lst.iter(&storage).all(pred);
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
    Var left = a.car, right = b.car;
    if (fn) values.push(fn.apply_values(left, right));
    else values.push(%($left $right));
  }
  return values;
}

/** Maps `fn` over aligned pairs from `a` and `b`.
    A null callback returns `nil` without examining either `List`; otherwise
    this has the length, order, ownership, and failures of `List.zip_with`.
*/
List List.map2(List a, List b, Func fn) {
  if (!fn) return NULL;
  return a.zip_with(b, fn);
}

// reshaping

/** Returns a copy of `lst` ordered by `Var.compare`.
    `lst` is unchanged. There is no comparator parameter. `Var.compare` orders
    the element tags involved, so a mixed-kind `List` still sorts. A `List` of
    fewer than two cells is returned as it stands.
    Raises: whatever element comparison raises, or `<alloc-fail>` while
    constructing the result.
*/
Self List.sort(Self lst) {
  if (!lst || !lst.cdr()) return lst;
  Array values = $auto(lst);
  values.sort();
  return values;
}

/** Returns a stable sorted copy using `Array.sort_with`'s callback contract.
    The input List is unchanged. Fewer than two cells return unchanged without
    a callback. Raises: allocation and the comparator's ordinary causes.
*/
Self List.sort_with(Self lst, Func compare) {
  if (!lst || !lst.cdr()) return lst;
  Array values = $auto(lst);
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
  Array values = $auto(lst);
  values.sort_by(key);
  return values;
}

/** Returns a copy of `lst` with later duplicates removed.
    The first occurrence of each value is kept and the original order is
    preserved. Duplicate detection runs through `Iter.unique`, whose state is
    held inside a `Scope` bracket that is released before returning. A `List`
    of fewer than two cells is returned as it stands.
    Raises: causes from `Map` hashing or equality, or `<alloc-fail>` or
    `<size-limit>` while constructing the result.
*/
meta native Self List.unique(Self lst) {
  if (!lst || !lst.cdr()) return lst;
  $scope() {
    struct Iter iter_storage, unique_storage;
    Iter iter = lst.iter(&iter_storage);
    Iter unique = iter.unique(&unique_storage);
    return unique;
  }
}

/** Flattens one level of nested `List`s into a canonical result.
    A nested `nil` contributes no element, non-`List` values retain their
    identity, and `nil` returns `nil`.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
meta native Self List.flatten(Self lst) {
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

/** Recursively flattens every nested `List` into a canonical result.
    Nested `nil` contributes no element and `nil` returns `nil`.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
meta native Self List.flatten_all(Self lst) {
  if (!lst) return lst;
  Array values = $auto([]);
  _flatten_into(values, lst);
  return values;
}

static void _flatten_into(Array values, List lst) {
  foreach (Var head, lst) {
    if (head is <list>) _flatten_into(values, head);
    else values.push(head);
  }
}

/** Recursively substitutes non-`List` nodes in `tree` from `alist`.
    Each association is a `List` whose first value is the key and whose second
    value is the replacement. Unmatched leaves are shared; `List` structure is
    rebuilt canonically, and `nil` returns `nil`.
    Raises: a cause from key equality, or `<alloc-fail>` or `<size-limit>`
    while constructing the result.
*/
meta native List List.sublis(List alist, List tree) {
  if (!tree) return NULL;
  return _sublis_node(alist, tree);
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
