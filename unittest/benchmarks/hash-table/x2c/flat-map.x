/*  flat-map.x -- benchmark specimen: MapIntInt with one combined array

    Copyright (c) 2026 Gary William Flake

    These are the three layouts used to choose MapIntInt's current storage:
    a 12-byte combined bucket, a 16-byte padded bucket, and parallel 4-byte
    hash and 8-byte entry arrays. They share the production fmix64 hash,
    Robin Hood displacement, calculated PSL, back-shift deletion, 0.75
    maximum load factor, Scope ownership, and Bytes storage, so their measured
    difference is the layout.

    Combined buckets place the hash beside its entry, so a match reaches the
    entry without a dependent record lookup. Two bucket widths are generated
    from one body: 12 bytes packs 5.3 buckets into a 64-byte line and straddles
    it, while 16 bytes fits exactly four and never straddles, at a third more
    memory.

    They are specimens, not runtime code: nothing in lib/ or src/ includes
    this file.
*/

#pragma once
#include "x2c.x"

typedef struct MapFlatIntInt {
  Scope *scope;
  Bytes buckets;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapFlatIntInt;

typedef struct MapMetaIntInt {
  Scope *scope;
  Bytes hashes, entries;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapMetaIntInt;

typedef struct MapWideIntInt {
  Scope *scope;
  Bytes buckets;
  unsigned used;
  unsigned capacity;
  unsigned mask;
} *MapWideIntInt;

typedef struct MapOrderIntInt {
  Scope *scope;
  Bytes hashes, entries, order, positions;
  unsigned used;
  unsigned filled;
  unsigned capacity;
  unsigned mask;
} *MapOrderIntInt;

#pragma private

#include <limits.h>
#include <string.h>

struct MapFlatBucket { unsigned hash; int key, val; };
struct MapWideBucket { unsigned hash, reserved; int key, val; };
struct MapMetaEntry { int key, val; };

static unsigned _flat_hash(int key) {
  uint64_t word = (unsigned) key;
  word ^= word >> 33;
  word *= 0xff51afd7ed558ccdull;
  word ^= word >> 33;
  word *= 0xc4ceb9fe1a85ec53ull;
  word ^= word >> 33;
  unsigned hash = (unsigned) word;
  return hash ? hash : -1;
}

static void _flat_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapFlatIntInt.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _flat_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapFlatIntInt.insert") (capacity $capacity));
}

static void _wide_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapWideIntInt.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _wide_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapWideIntInt.insert") (capacity $capacity));
}

static void _meta_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapMetaIntInt.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _meta_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapMetaIntInt.insert") (capacity $capacity));
}

static void _flat_bad_arg(String owner) {
  raise %(bad-arg (owner $owner));
}

static void _flat_bad_op(Symbol op) {
  raise %(bad-op (op $op));
}

static void _flat_bad_shift(Symbol op, int count) {
  raise %(bad-shift (op $op) (count $count) (width 32));
}

static void _flat_div_zero(Symbol op) {
  raise %(div-zero (op $op));
}

static int _flat_update(volatile int *slot, Symbol op, int rhs) {
  int current = slot[0];
  unsigned a, b, raw;
  memcpy(&a, &current, sizeof a);
  memcpy(&b, &rhs, sizeof b);
  switch (op) {
    case <+>: raw = a + b; break;
    case <->: raw = a - b; break;
    case <*>: raw = a * b; break;
    case <&>: raw = a & b; break;
    case <|>: raw = a | b; break;
    case <^>: raw = a ^ b; break;
    case </>: case <%>:
      if (!rhs) {
        _flat_div_zero(op);
      }
      if (current == INT_MIN && rhs == -1)
        raw = op == </> ? (unsigned) INT_MIN : 0u;
      else raw = op == </> ? (unsigned) (current / rhs)
                           : (unsigned) (current % rhs);
      break;
    case <"<<">: case <">>">:
      if (rhs < 0 || rhs >= 32) {
        _flat_bad_shift(op, rhs);
      }
      if (op == <"<<">) raw = a << rhs;
      else if (!rhs) raw = a;
      else if (!(a & 0x80000000u)) raw = a >> rhs;
      else raw = (a >> rhs) | (~0u << (32 - rhs));
      break;
    default: _flat_bad_op(op);
  }
  int result;
  memcpy(&result, &raw, sizeof result);
  slot[0] = result;
  return result;
}

/*  One combined-bucket family. The bucket width is the only difference
    between the two expansions below.
*/
macro Unit $flat.family(
  Type $map, Type $storage, Type $bucket, Literal $owner,
  Name $reinsert_error, Name $insert_error
) => {
  $map $map.new(void);
  $map $map.new_capacity(unsigned);
  void $map.free($map);
  unsigned $map.len($map);
  int $map.try_get($map, int, int *);
  void $map.set($map, int, int);
  int $map.updateindex($map, int, Symbol, int);
  int $map.try_del($map, int, int *);
  int $map.try_next($map, unsigned *, int *, int *);

  static void $map._free($map map) {
    if ((void *) map == 0) return;
    Bytes_free(map.buckets);
    Scope_free(map);
  }

  static $map $map._new_capacity($map unused, unsigned capacity) {
    (void) unused;
    $map map = Scope_malloc(sizeof($storage));
    map.scope = Scope_top();
    map.buckets = Bytes_new(sizeof($bucket));
    map.buckets = Bytes_append(map.buckets, 0, capacity);
    map.capacity = capacity;
    map.mask = capacity - 1;
    map.used = 0;
    return map;
  }

  static $bucket *$map._find($map map, int key) {
    unsigned key_hash = _flat_hash(key);
    $bucket *buckets = map.buckets;
    unsigned mask = map.mask, todo_start = key_hash & mask;
    unsigned cap = map.capacity;

    for (int todo_psl = 0; todo_psl < (int) cap; todo_psl++) {
      unsigned index = (todo_start + todo_psl) & mask;
      $bucket *bucket = buckets + index;
      if (bucket.hash == 0) break;
      if (bucket.hash == key_hash && bucket.key == key) return bucket;
      unsigned stored_start = bucket.hash & mask;
      int stored_psl = (cap + index - stored_start) & mask;
      if (stored_psl < todo_psl) break;
    }
    return 0;
  }

  static void $map._reinsert($map map, $bucket todo, int psl) {
    $bucket *buckets = map.buckets;
    unsigned mask = map.mask, todo_start = todo.hash & mask;
    unsigned cap = map.capacity;

    for (int todo_psl = psl; todo_psl < (int) cap; todo_psl++) {
      unsigned index = (todo_start + todo_psl) & mask;
      $bucket *bucket = buckets + index;
      if (bucket.hash == 0) {
        *bucket = todo;
        return;
      }
      unsigned stored_start = bucket.hash & mask;
      int stored_psl = (cap + index - stored_start) & mask;
      if (stored_psl < todo_psl) {
        $bucket swap = *bucket;
        *bucket = todo;
        todo = swap;
        todo_start = stored_start;
        todo_psl = stored_psl;
      }
    }
    (void) $reinsert_error(cap, psl);
  }

  static void $map._expand($map map) {
    $bucket *buckets = map.buckets;
    unsigned cap = map.capacity;
    if (cap > ~0u / 2) raise %(size-limit (size $cap));
    unsigned capacity = cap * 2;
    Bytes staged = Bytes_new(sizeof($bucket));
    defer Bytes_free(staged);
    staged = Bytes_append(staged, 0, capacity);

    $storage expanded = *map;
    expanded.buckets = staged;
    expanded.capacity = capacity;
    expanded.mask = capacity - 1;
    $map expanded_map = ($map) &expanded;
    for (unsigned i = 0; i < cap; i++) {
      $bucket *bucket = buckets + i;
      if (bucket.hash) expanded_map._reinsert(*bucket, 0);
    }
    Scope_move(Bytes_block(staged), map.scope);
    Scope_move((unsigned char *) staged - sizeof(Block), map.scope);
    map.buckets = expanded.buckets;
    map.capacity = expanded.capacity;
    map.mask = expanded.mask;
    staged = 0;
    Bytes_free((Bytes) buckets);
  }

  static int *$map._get_or_insert($map map, int key, int val, int *inserted) {
    *inserted = 0;
  retry:;
    unsigned key_hash = _flat_hash(key), mask = map.mask;
    unsigned todo_start = key_hash & mask;
    $bucket *buckets = map.buckets;
    unsigned cap = map.capacity;

    for (int todo_psl = 0; todo_psl < (int) cap; todo_psl++) {
      unsigned index = (todo_start + todo_psl) & mask;
      $bucket *bucket = buckets + index;

      if (bucket.hash == key_hash && bucket.key == key) return &bucket.val;

      if (bucket.hash == 0) {
        if (map.used >= (unsigned long) map.capacity * 3 / 4) {
          map._expand();
          goto retry;
        }
        bucket.hash = key_hash;
        bucket.key = key;
        bucket.val = val;
        map.used += 1;
        *inserted = 1;
        return &bucket.val;
      }

      unsigned stored_start = bucket.hash & mask;
      int stored_psl = (cap + index - stored_start) & mask;
      if (stored_psl < todo_psl) {
        if (map.used >= (unsigned long) map.capacity * 3 / 4) {
          map._expand();
          goto retry;
        }
        $bucket swap = *bucket;
        bucket.hash = key_hash;
        bucket.key = key;
        bucket.val = val;
        map.used += 1;
        *inserted = 1;
        map._reinsert(swap, stored_psl + 1);
        return &bucket.val;
      }
    }
    (void) $insert_error(cap);
  }

  /** Creates an empty map with `capacity` buckets, a power of two at
      least 2.
  */
  $map $map.new_capacity(unsigned capacity) {
    if (capacity < 2 || (capacity & (capacity - 1))) {
      (void) _flat_bad_arg($owner);
    }
    $map map = 0;
    return map._new_capacity(capacity);
  }

  /** Creates an empty map. */
  $map $map.new(void) {
    $map map = 0;
    return map._new_capacity(2);
  }

  /** Releases the map's storage before its Scope ends. */
  void $map.free($map map) {
    map._free();
  }

  /** Returns the number of live entries. */
  unsigned $map.len($map map) {
    return map ? map.used : 0;
  }

  /** Reads `key` into `out` and returns nonzero when it is present. */
  int $map.try_get($map map, int key, int *out) {
    if ((void *) map == 0 || !out) return 0;
    $bucket *bucket = map._find(key);
    if (!bucket) return 0;
    *out = bucket.val;
    return 1;
  }

  /** Stores `val` at `key`, replacing any existing value. */
  void $map.set($map map, int key, int val) {
    int inserted;
    int *stored = map._get_or_insert(key, val, &inserted);
    if (!inserted) stored[0] = val;
  }

  /** Applies `op` to the value at `key` and returns the result.
      A missing key under `<+>` inserts `rhs`, matching MapIntInt.
  */
  int $map.updateindex($map map, int key, Symbol op, int rhs) {
    if ((void *) map == 0) {
      (void) _flat_bad_arg($owner);
    }
    if (op == <+>) {
      int inserted;
      int *stored = map._get_or_insert(key, rhs, &inserted);
      if (inserted) return rhs;
      return _flat_update(stored, op, rhs);
    }
    $bucket *bucket = map._find(key);
    if (!bucket) {
      (void) _flat_bad_arg($owner);
    }
    return _flat_update(&bucket.val, op, rhs);
  }

  /** Removes `key`, reports its value in `out`, and returns nonzero when
      it was present.
  */
  int $map.try_del($map map, int key, int *out) {
    if ((void *) map == 0 || !out) return 0;
    $bucket *buckets = map.buckets;
    $bucket *bucket = map._find(key);
    if (!bucket) return 0;
    unsigned mask = map.mask, index = bucket - buckets;
    *out = bucket.val;
    bucket.hash = 0;
    map.used--;

    while (1) {
      unsigned empty = index;
      index = (index + 1) & mask;
      if (buckets[index].hash == 0 ||
          (buckets[index].hash & mask) == index) return 1;
      $bucket swap = buckets[empty];
      buckets[empty] = buckets[index];
      buckets[index] = swap;
    }
  }

  /** Yields the next live entry at or after `cursor` and advances it. */
  int $map.try_next($map map, unsigned *cursor, int *key, int *val) {
    if ((void *) map == 0 || !cursor || !key || !val) return 0;
    $bucket *buckets = map.buckets;
    while (*cursor < map.capacity) {
      $bucket *bucket = buckets + *cursor;
      *cursor += 1;
      if (bucket.hash != 0) {
        *key = bucket.key;
        *val = bucket.val;
        return 1;
      }
    }
    return 0;
  }
}

$flat.family(
  MapFlatIntInt, struct MapFlatIntInt, struct MapFlatBucket,
  "MapFlatIntInt", _flat_reinsert_error, _flat_insert_error
);

$flat.family(
  MapWideIntInt, struct MapWideIntInt, struct MapWideBucket,
  "MapWideIntInt", _wide_reinsert_error, _wide_insert_error
);

/*  The metadata variant. Same Robin Hood algorithm, same 12 bytes per
    bucket as MapFlatIntInt, but split so that probing touches only the
    4-byte hash array: sixteen candidates per cache line against five and a
    third. The key and value are in a parallel entry array, read once a
    hash matches, so a hit costs one dependent load and a miss costs none.
*/
static void MapMetaIntInt._free(MapMetaIntInt map) {
  if ((void *) map == 0) return;
  Bytes_free(map.hashes);
  Bytes_free(map.entries);
  Scope_free(map);
}

static MapMetaIntInt MapMetaIntInt._new_capacity(
  MapMetaIntInt unused, unsigned capacity) {
  (void) unused;
  MapMetaIntInt map = Scope_malloc(sizeof(struct MapMetaIntInt));
  map.scope = Scope_top();
  map.hashes = Bytes_new(sizeof(unsigned));
  map.hashes = Bytes_append(map.hashes, 0, capacity);
  map.entries = Bytes_new(sizeof(struct MapMetaEntry));
  map.entries = Bytes_append(map.entries, 0, capacity);
  map.capacity = capacity;
  map.mask = capacity - 1;
  map.used = 0;
  return map;
}

static int MapMetaIntInt._find(MapMetaIntInt map, int key) {
  unsigned key_hash = _flat_hash(key);
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned mask = map.mask, todo_start = key_hash & mask;
  unsigned cap = map.capacity;

  for (int todo_psl = 0; todo_psl < (int) cap; todo_psl++) {
    unsigned index = (todo_start + todo_psl) & mask;
    unsigned stored = hashes[index];
    if (stored == 0) break;
    if (stored == key_hash && entries[index].key == key) return (int) index;
    unsigned stored_start = stored & mask;
    int stored_psl = (cap + index - stored_start) & mask;
    if (stored_psl < todo_psl) break;
  }
  return -1;
}

static void MapMetaIntInt._reinsert(
  MapMetaIntInt map, unsigned todo_hash, struct MapMetaEntry todo, int psl) {
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned mask = map.mask, todo_start = todo_hash & mask;
  unsigned cap = map.capacity;

  for (int todo_psl = psl; todo_psl < (int) cap; todo_psl++) {
    unsigned index = (todo_start + todo_psl) & mask;
    unsigned stored = hashes[index];
    if (stored == 0) {
      hashes[index] = todo_hash;
      entries[index] = todo;
      return;
    }
    unsigned stored_start = stored & mask;
    int stored_psl = (cap + index - stored_start) & mask;
    if (stored_psl < todo_psl) {
      struct MapMetaEntry swap_entry = entries[index];
      hashes[index] = todo_hash;
      entries[index] = todo;
      todo_hash = stored;
      todo = swap_entry;
      todo_start = stored_start;
      todo_psl = stored_psl;
    }
  }
  (void) _meta_reinsert_error(cap, psl);
}

static void MapMetaIntInt._expand(MapMetaIntInt map) {
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned cap = map.capacity;
  if (cap > ~0u / 2) raise %(size-limit (size $cap));
  unsigned capacity = cap * 2;
  Bytes staged_hashes = Bytes_new(sizeof(unsigned));
  defer Bytes_free(staged_hashes);
  staged_hashes = Bytes_append(staged_hashes, 0, capacity);
  Bytes staged_entries = Bytes_new(sizeof(struct MapMetaEntry));
  defer Bytes_free(staged_entries);
  staged_entries = Bytes_append(staged_entries, 0, capacity);

  struct MapMetaIntInt expanded = *map;
  expanded.hashes = staged_hashes;
  expanded.entries = staged_entries;
  expanded.capacity = capacity;
  expanded.mask = capacity - 1;
  MapMetaIntInt expanded_map = (MapMetaIntInt) &expanded;
  for (unsigned i = 0; i < cap; i++)
    if (hashes[i]) expanded_map._reinsert(hashes[i], entries[i], 0);

  Scope_move(Bytes_block(staged_hashes), map.scope);
  Scope_move((unsigned char *) staged_hashes - sizeof(Block), map.scope);
  Scope_move(Bytes_block(staged_entries), map.scope);
  Scope_move((unsigned char *) staged_entries - sizeof(Block), map.scope);
  map.hashes = expanded.hashes;
  map.entries = expanded.entries;
  map.capacity = expanded.capacity;
  map.mask = expanded.mask;
  staged_hashes = 0;
  staged_entries = 0;
  Bytes_free((Bytes) hashes);
  Bytes_free((Bytes) entries);
}

static int *MapMetaIntInt._get_or_insert(
  MapMetaIntInt map, int key, int val, int *inserted) {
  *inserted = 0;
retry:;
  unsigned key_hash = _flat_hash(key), mask = map.mask;
  unsigned todo_start = key_hash & mask;
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned cap = map.capacity;

  for (int todo_psl = 0; todo_psl < (int) cap; todo_psl++) {
    unsigned index = (todo_start + todo_psl) & mask;
    unsigned stored = hashes[index];

    if (stored == key_hash && entries[index].key == key)
      return &entries[index].val;

    if (stored == 0) {
      if (map.used >= (unsigned long) map.capacity * 3 / 4) {
        map._expand();
        goto retry;
      }
      hashes[index] = key_hash;
      entries[index].key = key;
      entries[index].val = val;
      map.used += 1;
      *inserted = 1;
      return &entries[index].val;
    }

    unsigned stored_start = stored & mask;
    int stored_psl = (cap + index - stored_start) & mask;
    if (stored_psl < todo_psl) {
      if (map.used >= (unsigned long) map.capacity * 3 / 4) {
        map._expand();
        goto retry;
      }
      struct MapMetaEntry swap_entry = entries[index];
      hashes[index] = key_hash;
      entries[index].key = key;
      entries[index].val = val;
      map.used += 1;
      *inserted = 1;
      map._reinsert(stored, swap_entry, stored_psl + 1);
      return &entries[index].val;
    }
  }
  (void) _meta_insert_error(cap);
}

#pragma public

/** Creates an empty map with `capacity` buckets, a power of two at least 2. */
MapMetaIntInt MapMetaIntInt.new_capacity(unsigned capacity) {
  if (capacity < 2 || (capacity & (capacity - 1))) {
    (void) _flat_bad_arg("MapMetaIntInt.new_capacity");
  }
  MapMetaIntInt map = 0;
  return map._new_capacity(capacity);
}

/** Creates an empty map. */
MapMetaIntInt MapMetaIntInt.new(void) {
  MapMetaIntInt map = 0;
  return map._new_capacity(2);
}

/** Releases the map's storage before its Scope ends. */
void MapMetaIntInt.free(MapMetaIntInt map) {
  map._free();
}

/** Returns the number of live entries. */
unsigned MapMetaIntInt.len(MapMetaIntInt map) {
  return map ? map.used : 0;
}

/** Reads `key` into `out` and returns nonzero when it is present. */
int MapMetaIntInt.try_get(MapMetaIntInt map, int key, int *out) {
  if ((void *) map == 0 || !out) return 0;
  int index = map._find(key);
  if (index < 0) return 0;
  struct MapMetaEntry *entries = map.entries;
  *out = entries[index].val;
  return 1;
}

/** Stores `val` at `key`, replacing any existing value. */
void MapMetaIntInt.set(MapMetaIntInt map, int key, int val) {
  int inserted;
  int *stored = map._get_or_insert(key, val, &inserted);
  if (!inserted) stored[0] = val;
}

/** Applies `op` to the value at `key` and returns the result.
    A missing key under `<+>` inserts `rhs`, matching MapIntInt.
*/
int MapMetaIntInt.updateindex(MapMetaIntInt map, int key, Symbol op, int rhs) {
  if ((void *) map == 0) {
    (void) _flat_bad_arg("MapMetaIntInt.updateindex");
  }
  if (op == <+>) {
    int inserted;
    int *stored = map._get_or_insert(key, rhs, &inserted);
    if (inserted) return rhs;
    return _flat_update(stored, op, rhs);
  }
  int index = map._find(key);
  if (index < 0) {
    (void) _flat_bad_arg("MapMetaIntInt.updateindex");
  }
  struct MapMetaEntry *entries = map.entries;
  return _flat_update(&entries[index].val, op, rhs);
}

/** Removes `key`, reports its value in `out`, and returns nonzero when it
    was present.
*/
int MapMetaIntInt.try_del(MapMetaIntInt map, int key, int *out) {
  if ((void *) map == 0 || !out) return 0;
  int found = map._find(key);
  if (found < 0) return 0;
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned mask = map.mask, index = (unsigned) found;
  *out = entries[index].val;
  hashes[index] = 0;
  map.used--;

  while (1) {
    unsigned empty = index;
    index = (index + 1) & mask;
    if (hashes[index] == 0 || (hashes[index] & mask) == index) return 1;
    unsigned swap_hash = hashes[empty];
    struct MapMetaEntry swap_entry = entries[empty];
    hashes[empty] = hashes[index];
    entries[empty] = entries[index];
    hashes[index] = swap_hash;
    entries[index] = swap_entry;
  }
}

/** Yields the next live entry at or after `cursor` and advances it. */
int MapMetaIntInt.try_next(
  MapMetaIntInt map, unsigned *cursor, int *key, int *val) {
  if ((void *) map == 0 || !cursor || !key || !val) return 0;
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  while (*cursor < map.capacity) {
    unsigned index = *cursor;
    *cursor += 1;
    if (hashes[index] != 0) {
      *key = entries[index].key;
      *val = entries[index].val;
      return 1;
    }
  }
  return 0;
}

/*  The dense-order variant, measured and not adopted. Same Robin Hood table
    as MapMetaIntInt, plus two parallel unsigned arrays that make iteration a
    dense walk instead of a scan over mostly empty slots.

    Paired against MapMetaIntInt at 1,048,576 entries, eleven alternating
    samples, reproduced twice: iteration 5.78 to 2.60 ns and iteration after
    erasing half 7.12 to 3.20, both about 2.2 times faster; against erase-hit
    8.08 to 17.24 and insert-and-delete churn 9.67 to 14.42, both about twice
    as slow, with growing insertion 16% slower and lookups unchanged.

    The loss is not the insertion push, which is one write. Robin Hood moves
    entries during displacement and during back-shift deletion, and each move
    rewrites one `order` slot and one `positions` slot at a random address.
    Eager squeezing is what keeps the iteration win after deletions, and it
    doubles erase again; without it, iteration after erasing half is a wash.

    It also halves the distance to the fastest third-party tables rather than
    closing it. At 2.60 ns we remain about 3.4 times ankerl's 0.77, because
    `order` gives a dense sequence while the entries stay scattered, so every
    step is still a random load. Closing the rest means storing the entries
    themselves densely, which is unordered_dense, the slowest table in the
    udb3 cohort. The trade was declined for the general-purpose Map because
    the churn cost lands on udb3 mixed, where we are already 3x behind.

    `order` lists occupied slot indices in insertion order, with `_ORDER_GONE`
    marking a deleted one. `positions` maps a slot back to its place in
    `order`, so the two stay consistent when Robin Hood moves an entry. Both
    displacement during insertion and the back-shift during deletion move
    entries, so every such move rewrites one `order` slot and one `positions`
    slot; that, not the insertion push, is the real cost of the design.

    `filled` is the used length of `order`, live entries plus holes. When it
    reaches capacity the holes are squeezed out, which is O(capacity) work
    against at least a quarter of capacity operations since the last squeeze.

    Twelve bytes per slot become twenty. That is the trade being measured.
*/

#pragma private

#define _ORDER_GONE (~0u)

static void _order_reinsert_error(unsigned capacity, int probe) {
  raise %(invariant (owner "MapOrderIntInt.reinsert") (capacity $capacity)
          (probe $probe));
}

static void _order_insert_error(unsigned capacity) {
  raise %(invariant (owner "MapOrderIntInt.insert") (capacity $capacity));
}

static void MapOrderIntInt._free(MapOrderIntInt map) {
  if ((void *) map == 0) return;
  Bytes_free(map.hashes);
  Bytes_free(map.entries);
  Bytes_free(map.order);
  Bytes_free(map.positions);
  Scope_free(map);
}

static MapOrderIntInt MapOrderIntInt._new_capacity(
  MapOrderIntInt unused, unsigned capacity) {
  (void) unused;
  MapOrderIntInt map = Scope_malloc(sizeof(struct MapOrderIntInt));
  map.scope = Scope_top();
  map.hashes = Bytes_new(sizeof(unsigned));
  map.hashes = Bytes_append(map.hashes, 0, capacity);
  map.entries = Bytes_new(sizeof(struct MapMetaEntry));
  map.entries = Bytes_append(map.entries, 0, capacity);
  map.order = Bytes_new(sizeof(unsigned));
  map.order = Bytes_append(map.order, 0, capacity);
  map.positions = Bytes_new(sizeof(unsigned));
  map.positions = Bytes_append(map.positions, 0, capacity);
  map.capacity = capacity;
  map.mask = capacity - 1;
  map.used = 0;
  map.filled = 0;
  return map;
}

static int MapOrderIntInt._find(MapOrderIntInt map, int key) {
  unsigned key_hash = _flat_hash(key);
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned mask = map.mask, todo_start = key_hash & mask;
  unsigned cap = map.capacity;

  for (int todo_psl = 0; todo_psl < (int) cap; todo_psl++) {
    unsigned index = (todo_start + todo_psl) & mask;
    unsigned stored = hashes[index];
    if (stored == 0) break;
    if (stored == key_hash && entries[index].key == key) return (int) index;
    unsigned stored_start = stored & mask;
    int stored_psl = (cap + index - stored_start) & mask;
    if (stored_psl < todo_psl) break;
  }
  return -1;
}

/* Squeezes the holes out of `order` and rewrites every live slot's position.
   Costs one pass over `filled`, against at least capacity/4 operations since
   the last squeeze. */
static void MapOrderIntInt._squeeze(MapOrderIntInt map) {
  unsigned *order = map.order, *positions = map.positions;
  unsigned live = 0, filled = map.filled;
  for (unsigned i = 0; i < filled; i++) {
    unsigned slot = order[i];
    if (slot == _ORDER_GONE) continue;
    order[live] = slot;
    positions[slot] = live;
    live++;
  }
  map.filled = live;
}

static void MapOrderIntInt._reinsert(
  MapOrderIntInt map, unsigned todo_hash, struct MapMetaEntry todo, int psl,
  unsigned todo_pos) {
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned *order = map.order, *positions = map.positions;
  unsigned mask = map.mask, todo_start = todo_hash & mask;
  unsigned cap = map.capacity;

  for (int todo_psl = psl; todo_psl < (int) cap; todo_psl++) {
    unsigned index = (todo_start + todo_psl) & mask;
    unsigned stored = hashes[index];
    if (stored == 0) {
      hashes[index] = todo_hash;
      entries[index] = todo;
      order[todo_pos] = index;
      positions[index] = todo_pos;
      return;
    }
    unsigned stored_start = stored & mask;
    int stored_psl = (cap + index - stored_start) & mask;
    if (stored_psl < todo_psl) {
      struct MapMetaEntry swap_entry = entries[index];
      unsigned swap_pos = positions[index];
      hashes[index] = todo_hash;
      entries[index] = todo;
      order[todo_pos] = index;
      positions[index] = todo_pos;
      todo_hash = stored;
      todo = swap_entry;
      todo_pos = swap_pos;
      todo_start = stored_start;
      todo_psl = stored_psl;
    }
  }
  (void) _order_reinsert_error(cap, psl);
}

static void MapOrderIntInt._expand(MapOrderIntInt map) {
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned *old_order = map.order, *old_positions = map.positions;
  unsigned cap = map.capacity, old_filled = map.filled;
  if (cap > ~0u / 2) raise %(size-limit (size $cap));
  unsigned capacity = cap * 2;
  Bytes staged_hashes = Bytes_new(sizeof(unsigned));
  defer Bytes_free(staged_hashes);
  staged_hashes = Bytes_append(staged_hashes, 0, capacity);
  Bytes staged_entries = Bytes_new(sizeof(struct MapMetaEntry));
  defer Bytes_free(staged_entries);
  staged_entries = Bytes_append(staged_entries, 0, capacity);
  Bytes staged_order = Bytes_new(sizeof(unsigned));
  defer Bytes_free(staged_order);
  staged_order = Bytes_append(staged_order, 0, capacity);
  Bytes staged_positions = Bytes_new(sizeof(unsigned));
  defer Bytes_free(staged_positions);
  staged_positions = Bytes_append(staged_positions, 0, capacity);

  struct MapOrderIntInt expanded = *map;
  expanded.hashes = staged_hashes;
  expanded.entries = staged_entries;
  expanded.order = staged_order;
  expanded.positions = staged_positions;
  expanded.capacity = capacity;
  expanded.mask = capacity - 1;
  expanded.filled = 0;
  MapOrderIntInt expanded_map = (MapOrderIntInt) &expanded;

  /* Reinserting in `order` sequence rebuilds the dense array without holes
     and keeps iteration in insertion order across a doubling. */
  for (unsigned i = 0; i < old_filled; i++) {
    unsigned slot = old_order[i];
    if (slot == _ORDER_GONE) continue;
    unsigned position = expanded.filled;
    expanded.filled = position + 1;
    expanded_map._reinsert(hashes[slot], entries[slot], 0, position);
  }

  Scope_move(Bytes_block(staged_hashes), map.scope);
  Scope_move((unsigned char *) staged_hashes - sizeof(Block), map.scope);
  Scope_move(Bytes_block(staged_entries), map.scope);
  Scope_move((unsigned char *) staged_entries - sizeof(Block), map.scope);
  Scope_move(Bytes_block(staged_order), map.scope);
  Scope_move((unsigned char *) staged_order - sizeof(Block), map.scope);
  Scope_move(Bytes_block(staged_positions), map.scope);
  Scope_move((unsigned char *) staged_positions - sizeof(Block), map.scope);
  map.hashes = expanded.hashes;
  map.entries = expanded.entries;
  map.order = expanded.order;
  map.positions = expanded.positions;
  map.capacity = expanded.capacity;
  map.mask = expanded.mask;
  map.filled = expanded.filled;
  staged_hashes = 0;
  staged_entries = 0;
  staged_order = 0;
  staged_positions = 0;
  Bytes_free((Bytes) hashes);
  Bytes_free((Bytes) entries);
  Bytes_free((Bytes) old_order);
  Bytes_free((Bytes) old_positions);
}

static int *MapOrderIntInt._get_or_insert(
  MapOrderIntInt map, int key, int val, int *inserted) {
  *inserted = 0;
retry:;
  unsigned key_hash = _flat_hash(key), mask = map.mask;
  unsigned todo_start = key_hash & mask;
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned *order = map.order, *positions = map.positions;
  unsigned cap = map.capacity;

  for (int todo_psl = 0; todo_psl < (int) cap; todo_psl++) {
    unsigned index = (todo_start + todo_psl) & mask;
    unsigned stored = hashes[index];

    if (stored == key_hash && entries[index].key == key)
      return &entries[index].val;

    if (stored == 0) {
      if (map.used >= (unsigned long) map.capacity * 3 / 4) {
        map._expand();
        goto retry;
      }
      if (map.filled == cap) {
        map._squeeze();
        goto retry;
      }
      unsigned position = map.filled;
      hashes[index] = key_hash;
      entries[index].key = key;
      entries[index].val = val;
      order[position] = index;
      positions[index] = position;
      map.filled = position + 1;
      map.used += 1;
      *inserted = 1;
      return &entries[index].val;
    }

    unsigned stored_start = stored & mask;
    int stored_psl = (cap + index - stored_start) & mask;
    if (stored_psl < todo_psl) {
      if (map.used >= (unsigned long) map.capacity * 3 / 4) {
        map._expand();
        goto retry;
      }
      if (map.filled == cap) {
        map._squeeze();
        goto retry;
      }
      struct MapMetaEntry swap_entry = entries[index];
      unsigned swap_pos = positions[index];
      unsigned position = map.filled;
      hashes[index] = key_hash;
      entries[index].key = key;
      entries[index].val = val;
      order[position] = index;
      positions[index] = position;
      map.filled = position + 1;
      map.used += 1;
      *inserted = 1;
      map._reinsert(stored, swap_entry, stored_psl + 1, swap_pos);
      return &entries[index].val;
    }
  }
  (void) _order_insert_error(cap);
}

#pragma public

/** Creates an empty map with `capacity` buckets, a power of two at least 2. */
MapOrderIntInt MapOrderIntInt.new_capacity(unsigned capacity) {
  if (capacity < 2 || (capacity & (capacity - 1))) {
    (void) _flat_bad_arg("MapOrderIntInt.new_capacity");
  }
  MapOrderIntInt map = 0;
  return map._new_capacity(capacity);
}

/** Creates an empty map. */
MapOrderIntInt MapOrderIntInt.new(void) {
  MapOrderIntInt map = 0;
  return map._new_capacity(2);
}

/** Releases the map's storage before its Scope ends. */
void MapOrderIntInt.free(MapOrderIntInt map) {
  map._free();
}

/** Returns the number of live entries. */
unsigned MapOrderIntInt.len(MapOrderIntInt map) {
  return map ? map.used : 0;
}

/** Reads `key` into `out` and returns nonzero when it is present. */
int MapOrderIntInt.try_get(MapOrderIntInt map, int key, int *out) {
  if ((void *) map == 0 || !out) return 0;
  int index = map._find(key);
  if (index < 0) return 0;
  struct MapMetaEntry *entries = map.entries;
  *out = entries[index].val;
  return 1;
}

/** Stores `val` at `key`, replacing any existing value. */
void MapOrderIntInt.set(MapOrderIntInt map, int key, int val) {
  int inserted;
  int *stored = map._get_or_insert(key, val, &inserted);
  if (!inserted) stored[0] = val;
}

/** Applies `op` to the value at `key` and returns the result.
    A missing key under `<+>` inserts `rhs`, matching MapIntInt.
*/
int MapOrderIntInt.updateindex(
  MapOrderIntInt map, int key, Symbol op, int rhs) {
  if ((void *) map == 0) {
    (void) _flat_bad_arg("MapOrderIntInt.updateindex");
  }
  if (op == <+>) {
    int inserted;
    int *stored = map._get_or_insert(key, rhs, &inserted);
    if (inserted) return rhs;
    return _flat_update(stored, op, rhs);
  }
  int index = map._find(key);
  if (index < 0) {
    (void) _flat_bad_arg("MapOrderIntInt.updateindex");
  }
  struct MapMetaEntry *entries = map.entries;
  return _flat_update(&entries[index].val, op, rhs);
}

/** Removes `key`, reports its value in `out`, and returns nonzero when it
    was present. Each back-shifted entry also rewrites its `order` slot.
*/
int MapOrderIntInt.try_del(MapOrderIntInt map, int key, int *out) {
  if ((void *) map == 0 || !out) return 0;
  int found = map._find(key);
  if (found < 0) return 0;
  unsigned *hashes = map.hashes;
  struct MapMetaEntry *entries = map.entries;
  unsigned *order = map.order, *positions = map.positions;
  unsigned mask = map.mask, index = (unsigned) found;
  *out = entries[index].val;
  hashes[index] = 0;
  order[positions[index]] = _ORDER_GONE;
  map.used--;

  while (1) {
    unsigned empty = index;
    index = (index + 1) & mask;
    if (hashes[index] == 0 || (hashes[index] & mask) == index) break;
    unsigned swap_hash = hashes[empty];
    struct MapMetaEntry swap_entry = entries[empty];
    unsigned moved_pos = positions[index];
    hashes[empty] = hashes[index];
    entries[empty] = entries[index];
    order[moved_pos] = empty;
    positions[empty] = moved_pos;
    hashes[index] = swap_hash;
    entries[index] = swap_entry;
  }

  /* Squeeze once the holes outnumber the live entries, so a walk of `order`
     never touches more than two slots per live entry. Each squeeze costs one
     pass over `filled` and needs at least `used` deletions to earn, so the
     cost is amortized constant. */
  if (map.filled - map.used >= map.used) map._squeeze();
  return 1;
}

/** Yields the next live entry at or after `cursor` and advances it. The walk
    is over `order`, so it touches one entry per live element plus one per
    hole, instead of one per slot.
*/
int MapOrderIntInt.try_next(
  MapOrderIntInt map, unsigned *cursor, int *key, int *val) {
  if ((void *) map == 0 || !cursor || !key || !val) return 0;
  unsigned *order = map.order;
  struct MapMetaEntry *entries = map.entries;
  unsigned filled = map.filled;
  while (*cursor < filled) {
    unsigned slot = order[*cursor];
    *cursor += 1;
    if (slot != _ORDER_GONE) {
      *key = entries[slot].key;
      *val = entries[slot].val;
      return 1;
    }
  }
  return 0;
}
