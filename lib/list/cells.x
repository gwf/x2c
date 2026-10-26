/*  cells.x -- List cells operations */

// construction

/** Returns the List packed from the supplied values and explicit splices.
    An ordinary List argument remains one element. With no values, returns
    nil. The result has ordinary List identity and pool lifetime.
*/
List List.new(.... items) => items;

/** Returns the canonical cons cell for `head` and `tail`.
    Repeating the call with the same head bits and canonical tail returns the
    same cell from the active pool chain. An ancestor hit remains owned there;
    a miss belongs to the active pool. The tail is shared, and `nil` is the
    null pointer.
    Raises: `<void-op>` when `head` is `void`, or `<alloc-fail>`,
    `<size-limit>`, or `<invariant>` when a new canonical cell cannot be
    installed.
*/
List cons(Var head, List tail) {
  if (head is void) raise %(void-op (operation "List.cons"));
  return List.cons_in(Pool.current(), head, tail);
}

/** Method form of `cons`, with the same identity, lifetime, and failures. */
List List.cons(Var head, List tail) => cons(head, tail);

/** Returns `cons(head, tail)`, with the same identity and failures. */
List Var.cons(Var head, List tail)  => cons(head, tail);

// identity

/** Returns the stable hash of `List`'s exact head bits and tail identity.
    This is a constant-time hash of one cell, which canonical cells make
    sound. It reaches an element's content only when the `Var` word holds it:
    a small number, a `Symbol`, an `Atom`, a canonical `String`, or a nested
    `List`. An element the word points at hashes by identity, so a wide
    number boxed in a `Scope`, an `Array`, or a `Map` gives two equal-looking
    `List`s two hashes. Mutating an object referenced by the head does not
    change this hash.
*/
meta native unsigned List.hash(List lst) {
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
  return a.car.same(b.car) && a.cdr == b.cdr;
}

/** Compares `a` and `b` lexicographically through `Var.compare`.
    Element comparison causes propagate.
*/
meta native int List.compare(List a, List b) {
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

// promotion

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

    When another thread's pool promotes an equal cell first, that cell stays
    canonical; this one still survives, but `Pool.is_permanent` answers 0 for
    it. A null `lst` returns itself unchanged.
*/
meta native Self List.promote(Self lst) {
  if (!lst) return lst;
  _promote_node(lst);
  return lst;
}

/* String cars and long Atom payloads promote through the String pool chain.
   List.cons_in callers can create cross-pool graphs, which this walk does
   not follow, and must preserve those borrowed lifetimes themselves. */
static void _promote_node(Var node) {
  if (node is <string>) return (void) String.promote(node);
  if (node is <lsym>) return (void) Atom.promote(node);
  if (node is not <list>) return;
  for (List cur = node; cur; cur = cur.cdr) {
    if (!Pool.current().promote(cur, cur)) break;
    _promote_node(cur.car);
  }
}

/** Proves `lst` and its canonical children safe beyond every active pool.
    Returns 1 when the complete value is `nil`, already permanent, or can be
    promoted to the outermost `List` and `String` pools. Returns 0 when an
    active pool does not own part of the value. A zero result may follow
    successful promotion of an earlier cell or child. A thread that loses a
    concurrent promotion of an equal value still gets 1, though
    `Pool.is_permanent` answers 0 for its surviving copy.
    Raises: `<alloc-fail>` when promotion metadata cannot be allocated.
*/
int List.try_own(List lst) => !lst || _try_own_node(lst);

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
