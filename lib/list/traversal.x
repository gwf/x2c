/*  traversal.x -- List traversal operations */

// accessors

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

// traversal

/** Initializes caller-owned `dest` as a forward iterator over `lst`.
    The iterator borrows the immutable cells and yields their stored `Var` bits
    without retaining them, so the owning pool must outlive iteration. A null
    `dest` returns NULL; `nil` produces an exhausted iterator.
*/
Iter List.iter(List lst, Iter dest) {
  if (!dest) return NULL;
  return dest.init(lst, _next, lst);
}

// indexing

/** Returns the last value in `lst`, or `void` when it is empty. */
Var List.last(List lst) {
  if (!lst) return void;
  List tail;
  while ((tail = lst.cdr())) lst = tail;
  return lst.car();
}

/** Reports whether `lst` contains `key` by `Var` equality. */
int List.contains(List lst, Var key) => lst.index(key) != -1;

/** Returns the first index of `key`, or -1 when absent. */
meta native int List.index(List l, Var key) {
  for (int index = 0; l; l = l.cdr(), index++) if (l.car == key) return index;
  return -1;
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

/** Returns the shared tail beginning `n` cells in.
    Returns `nil` past the end and `list` itself when `n` is nonpositive.
*/
meta native Self List.nth_cdr(Self list, int n) {
  while (n-- > 0 && list) list = list.cdr();
  return list;
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

/** Returns the second value of the first association whose key equals `key`.
    Nil entries are skipped. A missing association and a missing second value
    both return `void`, so the two cases look the same here.
*/
Var List.assoc(List list, Var key) {
  foreach (List pair in list) {
    if (!pair) continue;
    Var (pair_key, value) = pair;
    if (pair_key == key) return value;
  }
  return void;
}



/** Writes the next element, advances `cursor`, and returns one.
    Initialize the caller-owned cursor to `lst`. A null pointer or an
    exhausted cursor returns zero without changing `cursor` or `out`. The
    cells are immutable, so only releasing the owning pool invalidates a
    cursor.

    `foreach (Var item in lst)` compiles to this loop.
*/
inline int List.try_next(List lst, List &?cursor, Var &?out) {
  if (!cursor) return 0;
  if (!out) return 0;
  List rest = cursor;
  if (!rest) return 0;
  out = rest.car();
  cursor = rest.cdr;
  return 1;
}

/** Returns the first `count` elements of `list`.
    When `count` reaches or exceeds the length, `list` itself comes back, the
    same pointer. `List`s are immutable, so sharing it is safe. Otherwise fresh
    canonical cells are built for the prefix.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing that prefix.
*/
meta native Self List.head(Self list, unsigned count) {
  List original = list, Array values = auto [];
  while (list && count--) {
    values.push(list.car);
    list = list.cdr();
  }
  if (!list) return original;
  return values;
}

/** Returns the last `count` elements of `list`.
    The result is an existing tail of `list`, so nothing is allocated. When
    `count` reaches or exceeds the length, the whole `list` comes back.
*/
meta native Self List.tail(Self list, unsigned count) {
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

/** Returns every `step`th element from `start` up to exclusive `stop`.
    Negative bounds count from the end. `step` must be positive.
    Raises: `<bad-arg>` when `step` is less than 1, or `<alloc-fail>` while
    constructing the result.
*/
meta native Self List.subseq(Self list, int start, int stop, int step) {
  if (step < 1) raise %(bad-arg (operation "List.subseq") (step $step));
  int span = x2c_normalize_slice(start, stop, step, list.len());
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
meta native Self List.getslice(Self list, int start, int stop, int step) {
  if (!step) raise %(bad-arg (operation "List.getslice") (step $step));
  int len = list.len(), span = x2c_normalize_slice(start, stop, step, len);
  if (step == 1 && start == 0 && span == len &&
      (!list || _is_active_canonical(list))) return list;
  if (step > 0) return _collect_subseq(list, start, step, span);
  if (span <= 0) return NULL;
  Array source = auto list;
  Array values = auto [];
  for (int i = 0; i < span; i++) values.push(source[start + i * step]);
  return values;
}



/** Returns the number of cells in `lst` in O(n) time. */
int List.len(List lst) {
  int len = 0;
  for (List l = lst; l; l = l.cdr()) len++;
  return len;
}

// unpacking

/** Writes at most `destination_count` elements through `List` pointers.
    Returns the number written. Extra source cells are left unread, and a
    short source leaves remaining destinations untouched. Each source value is
    decoded as a `List`, so another tag writes `nil`; a null destination is
    skipped but still counted.
    Raises: `<size-limit>` when `destination_count` exceeds `INT_MAX`. The
    failure occurs before any destination is written.
*/
int List.unpack_n(List src, unsigned destination_count, ...) {
  va_list ap;
  va_start(ap, destination_count);
  int count = _unpack_va(src, destination_count, ap, 1);
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
  int count = _unpack_va(src, destination_count, ap, 0);
  va_end(ap);
  return count;
}

/** Method form of `car`: the head of `lst`, or `void` when `lst` is `nil`. */
inline Var  List.car(List lst)     => car(lst);



/** Returns the head of `x`, or `void` when `x` is `nil`. */
inline Var  car(List x)  => x ? x.car : void;

/** Method form of `cdr`: the tail of `lst`, or `nil` when `lst` is `nil`. */
inline Self List.cdr(Self lst)     => cdr(lst);

/** Returns the tail of `x`, or `nil` when `x` is `nil`.
    Nil-safe like `car`. The tail is the same canonical structure the cell was
    built from.
*/
inline List cdr(List x)  => x ? x.cdr : NULL;

static int _next(Iter iter, Var *out) {
  List lst = iter.state;
  if (!lst) return 0;
  *out = lst.car();
  lst = lst.cdr;
  iter.state = lst;
  return 1;
}

static List _collect_subseq(List list, int start, int step, int span) {
  if (span <= 0) return NULL;
  for (int i = 0; list && i < start; i++) list = list.cdr();
  Array values = auto [];
  while (list && span--) {
    values.push(list.car);
    for (int i = 0; list && i < step; i++) list = list.cdr();
  }
  return values;
}

static int _is_active_canonical(List list) =>
  Pool.current().lookup(list) === list;

/* Reads each destination from `ap` as a `List *` when `lists` is set, and as
   a `Var *` otherwise. */
static int _unpack_va(List src, unsigned n, va_list ap, int lists) {
  if (n > INT_MAX) raise %(size-limit (operation "List.unpack_n") (count $n));
  int count = 0;
  for (; src && count < n; src = src.cdr(), count++) {
    if (lists) {
      List *dst = va_arg(ap, List *);
      if (dst) *dst = src.car();
    }
    else {
      Var *dst = va_arg(ap, Var *);
      if (dst) *dst = src.car();
    }
  }
  return count;
}
