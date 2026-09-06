/*  map.x -- hash table mapping `Var` keys to `Var` values

    Copyright (c) 2025 Gary William Flake

    `Map` uses Robin Hood hashing split across two scope-owned `Block`s. The
    hash
    `Block` holds one 32-bit hash per bucket; the entry `Block` holds the `Var`
    key
    and value at the same bucket index. Lookups probe the compact hash `Block`
    and touch an entry only when its hash matches. Capacity is always a power
    of two and probe distances are computed as needed.

    Bucket state   hash
    ------------   ----
    empty          0
    occupied       >0

    Deletion back-shifts hashes and entries together to close holes.
    Structural mutation invalidates traversal state. Keys and values are
    stored as `Var` bits; the `Map` does not free pointer-bearing payloads or
    canonical values reachable through them.
*/

#pragma once
$(import "error-macros.xmacro")
$(import "private-keywords.xmacro")
#include "common.x"
#include "iter.x"

/** `Scope`-backed mutable hash table from `Var` keys to `Var` values.
    The `Map` records the `Scope` used for its two backing `Block`s. `Context`
    moves
    the `Map` allocation itself before recursively exporting those `Block`s.
    Stored `Var` bits are shallow and retain no pointee; those values must
    remain
    valid while the `Map` can read, compare, hash, or return them. A valid
    empty
    `Map` is allocated and distinct from NULL.
*/
typedef struct Map {
  Scope *scope, Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *Map;

#pragma private

#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>

#include "var.x"
#include "exception.x"
#include "scope.x"
#include "block.x"
#include "buffer.x"
#include "varconvert.x"
$(import "map-generics.xmacro")

// core data structures
/* A record and its parallel nonzero hash occupy the same bucket. Both Vars are
   shallow copies; insertion never adopts storage reachable through them. */
struct MapRecord {  Var key, val; };

static void _reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "Map.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _insert_error(unsigned capacity) {
  raise %(invariant (owner "Map.insert") (capacity $capacity));
}

static Var *_record_key(Map map, unsigned index) {
  struct MapRecord *records = map.entries;
  return &records[index].key;
}

static Var *_record_value(Map map, unsigned index) {
  struct MapRecord *records = map.entries;
  return &records[index].val;
}

$map.var.family(
  _map_key_hash, _map_key_equal, _map_value_equal, _map_value_valid);

/* Var.hash normalizes zero because the hash array reserves it for an empty
   bucket. Array and Map keys hash and compare by identity, so changing their
   contents cannot strand a bucket or merge distinct keys. */
/* Generated growth builds and reinserts into two staged Blocks before changing
   the Map, so allocation failure leaves the installed table alone. A new entry
   is not written until hashing, equality, value validation, and any required
   growth finish. Growth is published before the incoming key's retry probe,
   so a callback transfer on that retry may leave capacity and bucket order
   changed. Final Robin Hood displacement writes as it walks; its invariant
   guard diagnoses a broken table and does not promise rollback. Deletion alone
   rearranges an installed cluster in place by back-shifting it. */
$map.core.family(
  Map, struct Map, Var, Var, unsigned, struct MapRecord,
  _map_key_hash, _map_key_equal, _map_value_equal, _map_value_valid,
  _record_key, _record_value,
  _reinsert_error, _insert_error);

/** Returns a fresh empty `Map` with exactly `capacity` slots.
    `Pool` uses this internal constructor to reuse a previous child's proven
    power-of-two table size. `capacity` must be a power of two of at least
    two. The public constructor is `Map.new`.
    Raises: `<bad-arg>` when `capacity` is not a valid table capacity, or
    `<alloc-fail>` / `<size-limit>` when initial storage cannot be allocated.
*/
Map Map.new_capacity(unsigned capacity) {
  if (capacity < 2 || (capacity & (capacity - 1)))
    raise %(bad-arg (owner "Map.new_capacity") (capacity $capacity));
  Map map = NULL;
  return map._core_new_capacity(capacity);
}

/** Returns a fresh empty `Map` in the current scope.
    Every call allocates, so two `Map.new()` results are distinct objects
    even though both are empty. The literal `%{}` calls this constructor.
    The `Map` and its growing storage belong to the scope in which it was
    created. An empty `Map` is an allocated object, never a null pointer.
    A bare `if (...)` uses `Map.truth` and tests content; use an
    explicit `(void *) map != NULL` comparison when pointer presence matters.

    It starts with two buckets, the smallest table whose mask is nonzero, and
    doubles from there.

    Keys and values are both `Var`, so one `Map` may be heterogeneous. Key by
    `String`, `Symbol`, `Atom`, number, or `List`: those hash by content.
    `Array` and `Map` keys hash and compare by identity, so distinct objects
    remain distinct keys even when their contents are equal.
    Raises: `<alloc-fail>` or `<size-limit>` when initial
    storage cannot be allocated. */
Map Map.new(void) => Map.new_capacity(2);

/** Returns the number of key/value pairs in `map`.
    O(1), and the emptiness test for a `Map`, because an empty `Map` is a
    nonnull
    object. This counts live entries. The table keeps more slots than
    entries to hold its load factor, so `Map.len` is not the allocation
    size. `map` must be nonnull.
*/
unsigned Map.len(Map map) => map.used;

/** Writes the value stored under `key` to `out` and returns nonzero when the
    key is present.
    Prefer this form. It reports presence separately from the payload, so it
    stays correct for every storable value, raw `Null` included. `out` is left
    untouched when the key is absent, and a null `map` or a null `out`
    reports absence rather than failing.

    `Array` and `Map` keys hash and compare by identity; changing their
    contents preserves lookup through the same object. Other keys use `Var`
    equality after a hash probe. `String`s, `Symbol`s, `Atom`s, numbers, and
    `List`s hash and compare by content.

    ```x2c
    ~Map ages = %{"ada": 36, "grace": 45};
    Var found;
    if (ages.try_get(%"ada", &found)) printf("%s\n", found.repr());
    if (!ages.try_get(%"nobody", &found)) printf("absent\n");
    ```
    Raises: `<void-op>` when `key` is `void`, or a cause raised by custom key
    hashing or equality. */
int Map.try_get(Map map, Var key, Var *out) => map._core_try_get(&key, out);

/** Returns the value stored under `key`, or `void` when absent.
    A convenience over `Map.try_get`, kept because it reads well inside a
    larger expression. `void` as the missing-key answer is unambiguous
    because `Map.set` refuses to store `void`. It says nothing else about
    the miss, so prefer `Map.try_get` where absence has to be handled.

    `Array` and `Map` keys hash and compare by identity, so a fresh object
    with equal contents is a different key. Other keys use `Var` equality:
    `List`, `String`, `Symbol`, `Atom`, and numeric keys hash and compare by
    content.

    ```x2c
    ~Map by_list = %{};
    ~Map by_array = %{};
    by_list[%(1 2)] = %"found";
    by_array[%[1, 2]] = %"found";
    printf("list key: %s\n", by_list[%(1 2)].repr());
    printf("array key: %s\n", by_array[%[1, 2]].repr());
    ```

    That prints `"found"` for the `List` key and `void` for the `Array` key. An
    `Array` or `Map` key can only be found again through the very same object.
    Raises: `<void-op>` when `key` is `void`, or a cause raised by custom key
    hashing or equality. */
Var Map.get(Map map, Var key) {
  Var out;
  return map.try_get(key, &out) ? out : void;
}

/** Returns the value selected by bracket indexing.
    This is what `map[key]` lowers to, and it is `Map.get` in every respect,
    including identity comparison for `Array` and `Map` keys.
    Bracket reads do not report status; prefer `Map.try_get` when an absent
    key and a `void` result must be told apart.

    Indexed compound assignment and increment/decrement use
    `Map.updateindex` and `Map.postfixindex`, which look up the key
    once. Numeric `+=` inserts a missing key from its right-hand side; other
    compounds and increment/decrement require an existing key. The read,
    modify, and write happen in one call. That is not thread-safe
    synchronization.
    Raises: the same causes as `Map.get`.
*/
Var Map.getindex(Map map, Var key) => map.get(key);

/** Returns the value stored under `key`, or `defval` when it is absent.
    Nothing is inserted and `Map.len` does not change, unlike `Map.setdefault`.
    For counting, numeric `map[k] += amount` initializes an absent key from
    `amount`; use `getdefault` when a read needs a fallback without mutation.
    Raises: `<void-op>` when `key` is `void`, or a cause raised by custom key
    hashing or equality.
*/
Var Map.getdefault(Map map, Var key, Var defval) {
  Var val;
  return map.try_get(key, &val) ? val : defval;
}

/** Returns the value stored under `key`, inserting `defval` first when the
    key is absent.
    Lookup and insertion share one Robin Hood probe. When insertion occurs,
    `Map.len` grows and an outstanding `Map.try_next` cursor is
    invalidated. `key` may not be `void`, and `defval` may not be `void` when
    it must be inserted; an existing-key read never stores or validates the
    fallback. Use `Map.getdefault` when the fallback should not be stored.
    Allocation, validation, and callback failures do not insert a pair,
    although capacity and traversal order may change if growth finished before
    a retrying key callback transferred. An `<invariant>` raised after Robin
    Hood displacement begins does not promise rollback.
    Raises: `<void-op>` when `key` is `void`, or when the key is absent and
    `defval` is `void`; `<bad-arg>` for a null `Map`; `<size-limit>`,
    `<alloc-fail>`, or `<invariant>` while inserting; or a cause raised by
    custom key hashing or equality.
*/
Var Map.setdefault(Map map, Var key, Var defval) {
  if ((void *) map == NULL) raise %(bad-arg);
  if (key is void) raise %(void-op);
  int inserted;
  Var *stored = map._core_get_or_insert(&key, &defval, &inserted);
  return stored[0];
}

/** Returns nonzero when `key` is present in `map`, whatever its value.
    A null `map` reports absence rather than failing. Key comparison follows
    `Map.get`:
    `Array`s and `Map`s compare structurally but hash by identity, so only
    same-object lookup is reliable.
    Raises: `<void-op>` when `key` is `void`, or a cause raised by custom key
    hashing or equality.
*/
int Map.contains(Map map, Var key) =>
  map && map._core_find_index(&key, NULL) >= 0;

static void _set(Map map, Var key, Var val) {
  if ((void *) map == NULL) raise %(bad-arg);
  if (key is void || val is void) raise %(void-op);
  map._core_set(&key, &val);
}

/** Stores `val` under `key`, replacing any value already there.
    A `void` key or value raises. That refusal is what makes `void` usable
    as the missing-key answer everywhere else in this module. Raw `Null` is
    `Map` data on either side.

    Inserting a new key is structural and invalidates outstanding cursors and
    iterators even when no growth is needed. The table grows automatically to
    stay under its load factor; growth also rehashes every entry and may change
    traversal order. Replacing an existing value is non-structural.

    Keys hash by content for `String`s, `Symbol`s, `Atom`s, numbers, and
    `List`s.
    `Array`s and `Map`s compare structurally but hash by identity, so an
    `Array` key
    can only be retrieved reliably through the very same object. `Map.get`
    shows what that looks like. Allocation, validation, and callback failures
    do not install or replace a pair. If growth completed before a retrying
    custom key callback failed, capacity and traversal order may still have
    changed. An `<invariant>` raised after Robin Hood displacement begins does
    not promise rollback. Raises: `<bad-arg>` for a null `Map`,
    `<void-op>` when
    `key` or `val` is `void`; `<size-limit>`, `<alloc-fail>`, or `<invariant>`
    while inserting; or a cause raised by custom key hashing or equality. */
void Map.set(Map map, Var key, Var val) {
  _set(map, key, val);
}

/** Stores `val` under `key` and returns `val` as the expression result.
    This is what `map[key] = val` lowers to. The storing half is `Map.set`,
    including its rejection of a `void` key or value and its invalidation of
    outstanding cursors whenever a new key is inserted.
    Raises: `<bad-arg>` for a null `Map`, `<void-op>` when `key` or `val` is
    `void`; `<size-limit>`, `<alloc-fail>`, or `<invariant>` while inserting;
    or a cause raised by custom key hashing or equality.
*/
Var Map.setindex(Map map, Var key, Var val) {
  _set(map, key, val);
  return val;
}

/** Updates one `Map` value in place.
    The key is looked up once and an existing record-value slot is delegated
    to `Var.update`. Numeric `+` inserts a missing key with `rhs` as its
    initial value, equivalent to adding it to zero; the inserted value keeps
    the right-hand side's numeric tag. Other operations require an existing
    key.

    Successful insertion is structural and may invalidate traversal.
    Existing-key updates are non-structural and do not invalidate traversal.
    Allocation, validation, and callback failures during a missing-key insert
    install no pair, although completed growth may still change capacity and
    traversal order. An `<invariant>` after displacement begins does not
    promise rollback. A failed existing-key update leaves its value unchanged.
    Raises: `<bad-arg>` for a null `Map` or missing required key, `<void-op>`
    for a `void` key or right operand, `<size-limit>`, `<alloc-fail>`, or
    `<invariant>` while inserting for numeric `+`, a custom key callback
    cause, or any cause from `Var.update`.
*/
Var Map.updateindex(Map map, Var key, Symbol op, Var rhs) {
  if ((void *) map == NULL) raise %(bad-arg);
  if (key is void || rhs is void) raise %(void-op);
  X2CVarNumericInfo info;
  int numeric = Var.encoding_valid(rhs) && Var.numeric_info(rhs.tag(), &info);
  if (op == <+> && numeric) {
    int inserted;
    Var *stored = map._core_get_or_insert(&key, &rhs, &inserted);
    if (inserted) return rhs;
    return Var.update(stored, op, rhs);
  }
  long index = map._core_find_index(&key, NULL);
  if (index < 0) raise %(bad-arg (key $key));
  struct MapRecord *recs = map.entries;
  return Var.update(&recs[index].val, op, rhs);
}

/** Applies postfix increment or decrement to one existing `Map` value.
    The key is looked up once and the original value is returned. A missing
    key is not inserted.
    Raises: `<bad-arg>` for a null `Map` or missing key, `<void-op>` for a
    `void` key, a custom key callback cause, or any cause from `Var.postfix`.
    These failures leave the existing value unchanged.
*/
Var Map.postfixindex(Map map, Var key, Symbol op) {
  if ((void *) map == NULL) raise %(bad-arg);
  if (key is void) raise %(void-op);
  long index = map._core_find_index(&key, NULL);
  if (index < 0) raise %(bad-arg (key $key));
  struct MapRecord *recs = map.entries;
  return Var.postfix(&recs[index].val, op);
}

/** Removes `key`, writes the value it held to `out`, and returns nonzero
    when the key was present.
    Removal with a status result, symmetric with `Map.try_get`. `out` is
    untouched when the key is absent, and a null `map` or `out` reports
    absence rather than failing.

    Removal back-shifts adjacent hashes and entries to close the hole instead
    of leaving a tombstone. That keeps later probes short but rearranges the
    table, so it invalidates any outstanding `Map.try_next` cursor. `Map.len`
    drops but the allocation does not shrink. Raises: `<void-op>` when `key` is
    `void`, or a cause raised by custom key hashing or equality. */
int Map.try_del(Map map, Var key, Var *out) => map._core_try_del(&key, out);

/** Removes `key` and returns its value, or `void` when absent.
    A convenience over `Map.try_del`, useful when the removed value is all
    you want and a missing key is unremarkable. It is
    otherwise identical, cursor invalidation included. Because `void` is not
    storable, the absence result is unambiguous. Prefer `Map.try_del` when the
    status should be explicit or the output must remain unchanged on absence.
    Raises: the same causes as `Map.try_del`.
*/
Var Map.del(Map map, Var key) {
  Var out;
  return map.try_del(key, &out) ? out : void;
}

/** Adds exactly `pair_count` key/value pairs to `map` in argument order.
    Arguments alternate `Var` keys and values. A null `Map` returns NULL
    without
    reading them. Each completed pair remains if a later pair fails. Inserting
    a new key invalidates active traversal; replacing an existing value does
    not.
    Raises: the same causes as `Map.set`.
*/
Self Map.update_n(Self map, unsigned pair_count, ...) {
  if ((void *) map == NULL) return NULL;
  va_list ap;
  va_start(ap, pair_count);
  for (unsigned i = 0; i < pair_count; i++) {
    Var key = va_arg(ap, Var), val = va_arg(ap, Var);
    _set(map, key, val);
  }
  va_end(ap);
  return map;
}

/** Returns a new `Map` holding shallow copies of `map`'s key/value pairs.
    The copy is shallow and independent: inserting into one does not affect
    the other, but the two share whatever objects their keys and values point
    at. Because `Map`s are identity-bearing, plain assignment aliases instead
    of copying, so copy before handing a `Map` to code that may mutate it.

    For a nonnull source, the result is `Map.equal` to the original and never
    `==` to it. A null source returns a fresh empty `Map`,
    which is not equal to
    NULL. Because the copy is built by re-inserting entries, its traversal
    order may differ.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while
    constructing the result, or a cause raised by custom key hashing or
    equality.
*/
Self Map.copy(Self map) => map._core_copy();

/** Exports every key and value, rebuilds the table, then moves its `Block`s.
    The borrowed `export_value` callback runs synchronously for each stored
    key and value and may return replacement `Var`s. Rebuilding is required
    because an exported key may hash differently. On success the old backing
    `Block`s are freed, the rebuilt `Block`s move into `scope`, and the `Map`
    identity remains unchanged. `Context` moves that identity before this call
    to break cycles.

    A failure while staging leaves the `Map`'s original records, backing
    storage,
    and recorded `Scope` unchanged. Effects of callbacks that already
    completed,
    including nested exports, are not rolled back. Any failure while moving the
    rebuilt `Block`s occurs after the table has replaced the original. A null
    `Map`, callback, or `Scope` pointer does nothing. Raises: `<alloc-fail>`,
    `<size-limit>`, or `<invariant>` while rebuilding, or any cause from
    export, key hashing, or moving the rebuilt `Block`s. */
void Map.export_to(
  Map map, Context source, VarExportContextFn export_value, Scope *scope) {
  if ((void *) map == NULL || !export_value || !scope) return;
  Bytes old_hashes = map.hashes, old_entries = map.entries;

  /* Stage both arrays without publishing either one. A transfer frees the
     staged Blocks and leaves the original table installed; callback effects
     that happened before it remain the caller's responsibility. */
  Bytes rebuilt_hashes = Bytes.new(sizeof(unsigned));
  Bytes rebuilt_entries = Bytes.new(sizeof(struct MapRecord)), int rebuilt = 0;
  defer if (!rebuilt) rebuilt_hashes.free();
  defer if (!rebuilt) rebuilt_entries.free();
  rebuilt_hashes = rebuilt_hashes.append(NULL, map.capacity);
  rebuilt_entries = rebuilt_entries.append(NULL, map.capacity);
  struct Map exported = *map;
  exported.hashes = rebuilt_hashes;
  exported.entries = rebuilt_entries;
  foreach (Var (key, val), map) {
    struct MapRecord record = {
      .key = export_value(key, source),
      .val = export_value(val, source)
    };
    ((Map) &exported)._core_reinsert(record.key.hash(), record, 0);
  }
  map.hashes = rebuilt_hashes;
  map.entries = rebuilt_entries;
  rebuilt_hashes = NULL;
  rebuilt_entries = NULL;
  rebuilt = 1;
  old_hashes.free();
  old_entries.free();

  map.hashes.block().move_to(scope);
  map.entries.block().move_to(scope);
  map.scope = scope;
}

/** Copies every entry of `other` into `map` and returns `map`.
    This mutates `map` in place, which is the difference from `Map.copy`. Keys
    already present are overwritten, so `other` wins every conflict. A null
    `other` is a no-op, and a null `map` is replaced by a fresh
    `Map`, so use the
    return value. A new key structurally mutates the destination and
    invalidates its active cursors; replacing only existing values does not.
    Raises: `<alloc-fail>`, `<size-limit>`, or `<invariant>` while inserting,
    or a cause raised by custom key hashing or equality. A supplied destination
    is not rolled back; a newly created destination is discarded.
*/
Self Map.merge(Self map, Self other) => map._core_merge(other);

/** Yields the next occupied entry at or after `cursor`, advances it, and
    returns nonzero while entries remain.
    The cursor belongs to the caller: declare an `unsigned`, initialize it
    to zero, and pass its address.
    Status comes back separately from `key` and `val`, so an entry may hold
    raw `Null` on either side without that looking like exhaustion, and the
    outputs are left untouched once the walk is done.

    Entries arrive in bucket order, not insertion or sorted order, and that
    order changes when the table grows. Any structural
    mutation of `map` invalidates an outstanding cursor, including an
    insertion that triggers a rehash and a removal that back-shifts entries:
    collect what you need into an `Array` or a `List` first, then mutate.

    A null `Map` or any null output pointer returns zero without changing the
    other outputs. Exhaustion leaves `key` and `val` untouched.

    `foreach (Var (key, value), map)` reads both names out of this same cursor
    and is usually what you want. Use this loop when the traversal has to
    interleave with other work; for an `Iter` use `Map.iter`, `Map.keys`, or
    `Map.enumerate`.

    ```x2c
    ~Map ages = %{"ada": 36, "grace": 45};
    unsigned cursor = 0;
    Var key, val;
    while (ages.try_next(&cursor, &key, &val))
      printf("%s -> %s\n", key, val.repr());
    ```
*/
int Map.try_next(Map map, unsigned *cursor, Var *key, Var *val) =>
  map._core_try_next(cursor, key, val);

/** Returns nonzero when `map` contains at least one entry.
    A null or empty `Map` returns zero.
*/
int Map.truth(Map map) => map._core_truth();

static Var _box_var(Var value) => value;
static int _compare_var(Var a, Var b) => a.compare(b);
$map.core.observe(Map, Var, Var, struct MapRecord,
  _box_var, _box_var, _compare_var, _compare_var);

/** Compares `Map`s by size and then by sorted key/value contents.
    Identical handles compare equal; NULL sorts before a nonnull `Map`.
    Equal-size `Map`s are copied and sorted by `(key, value)`, then the sorted
    arrays are compared lexicographically. Key and value comparisons use
    `Var.compare`; neither `Map` is mutated.
    Raises: `<alloc-fail>` while creating temporary storage, or any cause from
    key or value comparison.
*/
int Map.compare(Map a, Map b) => a._core_compare(b);

static int _next(Iter iter, Var *out) {
  Map map = iter.obj;
  if ((void *) map == NULL) return 0;
  unsigned cursor = iter.state;
  Var key, val;
  if (!map.try_next(&cursor, &key, &val)) return 0;
  iter.state = cursor;
  *out = val;
  return 1;
}

static int _keys_next(Iter iter, Var *out) {
  Map map = iter.obj;
  if ((void *) map == NULL) return 0;
  unsigned cursor = iter.state;
  Var key, val;
  if (!map.try_next(&cursor, &key, &val)) return 0;
  iter.state = cursor;
  *out = key;
  return 1;
}

static int _enumerate_next(Iter iter, Var *out) {
  Map map = iter.obj;
  if ((void *) map == NULL) return 0;
  unsigned cursor = iter.state;
  Var key, val;
  if (!map.try_next(&cursor, &key, &val)) return 0;
  iter.state = cursor;
  *out = %($key $val);
  return 1;
}

/** Initializes `dest` as an iterator over `x`, yielding each value. Keys come
    from `Map.enumerate`, which pairs each one with its value the way
    `Iter.enumerate` pairs an index with an element.

    The caller owns the storage: declare a `struct Iter` and pass its address.
    The return value is that same `dest`, or `NULL` when `dest` is null. The
    iterator borrows `x`; both must outlive every pull. A null
    `Map` produces an
    exhausted iterator. Like a cursor, it is single-pass and is invalidated by
    any structural mutation.

    Neither constructing the iterator nor pulling from it raises.
*/
Iter Map.iter(Map x, Iter dest) {
  if (!dest) return NULL;
  return dest.init(x, _next, Var.new(<u32>, 0u));
}

/** Initializes `dest` as an iterator over `x`, yielding each key. The mirror
    of `Map.iter`, and like it, it allocates nothing.

    The caller owns the storage and the iterator borrows `x`; both must outlive
    every pull. A null `Map` produces an exhausted iterator. The iterator is
    single-pass, and any structural mutation of `x` invalidates it, as for
    `Map.iter`.

    Neither constructing the iterator nor pulling from it raises.
*/
Iter Map.keys(Map x, Iter dest) {
  if (!dest) return NULL;
  return dest.init(x, _keys_next, Var.new(<u32>, 0u));
}

/** Initializes `dest` as an iterator over `x`, yielding each entry as a
    `(key value)` two-element `List`. Destructure pairs with
    `foreach (Var (key, value), map.enumerate(&storage))` and
    `Var (key, value) = pair;`.

    Each yielded pair is a canonical `List` under the active pool chain; it may
    reuse an equal pair owned by an ancestor. Pair interning is work that plain
    iteration does not perform. `foreach (Var (key, value), map)` reads both
    names straight from the cursor and allocates nothing; prefer it unless an
    `Iter` is needed. The iterator borrows `x`, and both `x` and `dest`
    must outlive every pull. A null `Map` produces an exhausted iterator.

    Constructing the iterator does not raise. Pulling may raise
    `<alloc-fail>` or `<size-limit>` while interning a pair.
*/
Iter Map.enumerate(Map x, Iter dest) {
  if (!dest) return NULL;
  return dest.init(x, _enumerate_next, Var.new(<u32>, 0u));
}

/** Returns nonzero when `map1` and `map2` hold the same key/value pairs.
    A structural comparison, independent of insertion order and of table
    layout, so two `Map`s built by different routes still compare equal. `==`
    uses this operation; `===` remains the identity test. When used as keys
    of another `Map`, separately built equal `Map`s remain distinct keys.

    Values are compared with `Var` equality, so nested `Array`s and `Map`s also
    compare structurally. Two null handles compare equal; exactly one null
    handle compares unequal. Raises: a cause raised by key hashing, key
    equality, or value equality. */
int Map.equal(Map map1, Map map2) => map1._core_equal(map2);

/** Appends the readable representation of `map` to `out` in bucket order.
    Keys and values use `write_repr`; a null or empty `Map` appends `{  }`.
    `out` must be nonnull.
    Raises: `<alloc-fail>` or `<size-limit>` while growing `out`, or a cause
    raised while rendering an entry. A failure leaves any prefix already
    appended.
*/
Buffer Map.write_repr(Map map, Buffer out) => map._core_write(out, <repr>);

/** Appends the `Map` display text to `out`, using each entry's `write_str`.
    `Map.str` calls this to build its result. An empty `Map` displays as `{ }`,
    including when nested in another container. Nonempty entries appear in
    bucket order. `out` must be nonnull.
    Raises: `<alloc-fail>` or `<size-limit>` while growing `out`, or a cause
    raised while rendering an entry. A failure leaves any prefix already
    appended.
*/
Buffer Map.write_str(Map map, Buffer out) {
  if (!map) return out.write("{ }");
  return map._core_write(out, <str>);
}

/** Returns the display `String` of `map`.
    Any empty `Map` renders as `{ }`, one space narrower than the `{  }` that
    `Map.repr` gives for the same `Map`. The test is `Map.truth`, so emptiness
    selects it, not null. Nonempty entries appear in
    bucket order and use their display forms.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result, or
    a cause raised while rendering an entry.
*/
String Map.str(Map map) {
  Buffer buf = Buffer.new(0);
  map.write_str(buf);
  return buf.str_free();
}

/** Returns the readable `{ key: value, ... }` representation of `map`.
    Keys and values are rendered with their own `repr`, so `String`s appear
    quoted and `Symbol`s in angle brackets. Entries appear in hash-slot order,
    which keeps the entry order stable only while that table remains unchanged;
    separately built `Map`s may use a different order. Use `Map.equal` to
    compare
    contents. An empty `Map` renders as `{  }`.

    `Map.str` has the same shape but uses each element's `str` form.
    `Map.write_repr` and `Map.write_str` append to a `Buffer` instead of
    allocating a `String`, and are what the two `String` forms materialize.
    Raises:
    `<alloc-fail>` or `<size-limit>` while constructing the result, or a cause
    raised while rendering an entry. */
String Map.repr(Map map) {
  Buffer buf = Buffer.new(0);
  map.write_repr(buf);
  String result = buf.str_free();
  return result;
}
