/*  grouped.x -- grouped storage for Map families

    Copyright (c) 2026 Gary William Flake

    Controls hold seven-bit fingerprints, 128 for empty, and 254 for deleted.
    Tiny tables pad controls to sixteen bytes. An unsigned tombstone count
    follows the padded controls. Var Map and Pool keep full hashes after it.
    Both regions move with the control allocation.
*/

/* Cached families retain the complete key hash for rebuilding. Other families
   recompute it through their existing key hash. These inline operations let
   one storage generator serve both record shapes without runtime dispatch. */
macro Unit $map.grouped.rehashed.records(
  Type $record, Name $hash, Name $record_hash, Name $remember_hash
) {
  static inline unsigned $record_hash($record *record) => $hash(&record.key);
  static inline void $remember_hash($record *record, unsigned hash) {
    (void) record;
    (void) hash;
  }
}

macro Unit $map.grouped.cached.records(
  Type $record, Name $record_hash, Name $remember_hash
) {
  static inline unsigned $record_hash($record *record) => record.cached_hash;
  static inline void $remember_hash($record *record, unsigned hash) {
    record.cached_hash = hash;
  }
}

macro Unit $map.grouped.storage.family(
  Type $map, Type $storage, Type $key, Type $value,
  Type $entry,
  Name $hash, Name $key_equal, Name $value_equal, Name $value_valid,
  Name $key_at, Name $value_at, Name $reinsert_error, Name $insert_error,
  Name $record_hash, Name $remember_hash, Literal $grow_tail,
  Literal $side_hashes, Literal $owned
) {
  static unsigned _control_count(unsigned capacity) =>
    capacity < 16 ? 16 : capacity;

  static unsigned *_deleted($map map) =>
    (unsigned *) ((unsigned char *) map.hashes + _control_count(map.capacity));

  static unsigned _lanes(unsigned capacity) =>
    capacity < 16 ? (1u << capacity) - 1 : 65535u;

  static Bytes $map.new_controls($map unused, unsigned capacity) {
    (void) unused;
    unsigned count = _control_count(capacity);
    size_t bytes = (size_t) count + sizeof(unsigned);
    if ($side_hashes) bytes += (size_t) capacity * sizeof(unsigned);
    Bytes controls = Bytes_new(bytes);
    controls = controls.append(0, 1);
    memset(controls, 128, count);
    return controls;
  }

  static inline unsigned *$map.full_hashes($map map) => _deleted(map) + 1;

  static void $map.free_table($map map) {
    if ((void *) map == NULL) return;
    if ($owned && map.scope) map.scope.destroy();
    map.hashes.free();
    map.entries.free();
    Scope_free(map);
  }

  static $map $map.new_table($map unused, unsigned capacity) {
    (void) unused;
    $map map = Scope_malloc(sizeof($storage));
    map.scope = $owned ? NULL : *Scope_top();
    map.hashes = map.new_controls(capacity);
    map.entries = Bytes_new(sizeof($entry));
    map.entries = map.entries.append(0, capacity);
    map.capacity = capacity;
    map.mask = capacity - 1;
    map.used = 0;
    return map;
  }

  static long $map.find_hashed($map map, $key *key, unsigned key_hash) {
    unsigned char *controls = map.hashes;
    $entry *entries = map.entries;
    unsigned *full_hashes = $side_hashes ? map.full_hashes() : NULL;
    unsigned group_mask = map.mask >> 4, group = key_hash & group_mask;
    unsigned char fingerprint = key_hash >> 25;
    for (unsigned step = 0; step <= group_mask; step++) {
      unsigned start = group * 16;
      unsigned matches = x2c_map_group_match(controls + start, fingerprint);
      if (matches && !$side_hashes) __builtin_prefetch(entries + start, 0, 3);
      while (matches) {
        unsigned index = start + __builtin_ctz(matches);
        if ($side_hashes) __builtin_prefetch(entries + index, 0, 3);
        if ((!$side_hashes || full_hashes[index] == key_hash) &&
            $key_equal($key_at(map, index), key)) return (long) index;
        matches &= matches - 1;
      }
      if (x2c_map_group_match(controls + start, 128)) return -1;
      group = (group + step + 1) & group_mask;
    }
    return -1;
  }

  static long $map.find_index($map map, $key *key) =>
    map.find_hashed(key, $hash(key));

  static int $map.try_get_entry($map map, $key *key, $value *out) {
    if ((void *) map == NULL || !out) return 0;
    long index = map.find_index(key);
    if (index < 0) return 0;
    *out = *$value_at(map, (unsigned) index);
    return 1;
  }

  /* Rebuild owns a unique, valid source set and an empty destination. */
  static void $map.reinsert_unique(
    $map map, unsigned key_hash, const $entry *record) {
    unsigned char *controls = map.hashes;
    $entry *entries = map.entries;
    unsigned *full_hashes = $side_hashes ? map.full_hashes() : NULL;
    unsigned group_mask = map.mask >> 4, group = key_hash & group_mask;
    unsigned lanes = _lanes(map.capacity);
    for (unsigned step = 0; step <= group_mask; step++) {
      unsigned start = group * 16;
      unsigned empty = x2c_map_group_match(controls + start, 128) & lanes;
      if (empty) {
        unsigned index = start + __builtin_ctz(empty);
        entries[index] = *record;
        if ($side_hashes) full_hashes[index] = key_hash;
        else $remember_hash(&entries[index], key_hash);
        controls[index] = key_hash >> 25;
        map.used++;
        return;
      }
      group = (group + step + 1) & group_mask;
    }
    (void) $reinsert_error(map.capacity, 0);
  }

  static void _rebuild($map map, unsigned capacity) {
    unsigned char *controls = map.hashes;
    $entry *entries = map.entries;
    unsigned old_capacity = map.capacity;
    unsigned *full_hashes = $side_hashes ? map.full_hashes() : NULL;
    auto Bytes staged_hashes = map.new_controls(capacity);
    auto Bytes staged_entries = Bytes_new(sizeof($entry));
    staged_entries = staged_entries.append(0, capacity);
    $storage expanded = *map;
    expanded.hashes = staged_hashes;
    expanded.entries = staged_entries;
    expanded.capacity = capacity;
    expanded.mask = capacity - 1;
    expanded.used = 0;
    $map replacement = ($map) &expanded;
    for (unsigned i = 0; i < old_capacity; i++)
      if (controls[i] < 128)
        replacement.reinsert_unique(
          $side_hashes ? full_hashes[i] : $record_hash(&entries[i]),
          &entries[i]);
    Scope_move_before(staged_hashes.block(), map.hashes.block());
    Scope_move_before(
      (unsigned char *) staged_hashes - sizeof(Block),
      (unsigned char *) map.hashes - sizeof(Block));
    Scope_move_before(staged_entries.block(), map.entries.block());
    Scope_move_before(
      (unsigned char *) staged_entries - sizeof(Block),
      (unsigned char *) map.entries - sizeof(Block));
    map.hashes = expanded.hashes;
    map.entries = expanded.entries;
    map.capacity = expanded.capacity;
    map.mask = expanded.mask;
    map.used = expanded.used;
    staged_hashes = 0;
    staged_entries = 0;
    Bytes_free((Bytes) controls);
    Bytes_free((Bytes) entries);
  }

  __attribute__((noinline)) static $value *$map.grow_and_insert(
    $map map, $key *key, $value *value, int *inserted, unsigned capacity) {
    _rebuild(map, capacity);
    return map.get_or_insert(key, value, inserted);
  }

  static $value *$map.get_or_insert(
    $map map, $key *key, $value *value, int *inserted) {
  retry:;
    unsigned key_hash = $hash(key);
    unsigned char fingerprint = key_hash >> 25;
    unsigned char *controls = map.hashes;
    $entry *entries = map.entries;
    unsigned *full_hashes = $side_hashes ? map.full_hashes() : NULL;
    unsigned group_mask = map.mask >> 4, group = key_hash & group_mask;
    unsigned lanes = _lanes(map.capacity), available = ~0u;
    for (unsigned step = 0; step <= group_mask; step++) {
      unsigned start = group * 16;
      unsigned matches =
        x2c_map_group_match(controls + start, fingerprint) & lanes;
      if (matches && !$side_hashes) __builtin_prefetch(entries + start, 0, 3);
      while (matches) {
        unsigned index = start + __builtin_ctz(matches);
        if ($side_hashes) __builtin_prefetch(entries + index, 0, 3);
        if ((!$side_hashes || full_hashes[index] == key_hash) &&
            $key_equal($key_at(map, index), key)) {
          *inserted = 0;
          return $value_at(map, index);
        }
        matches &= matches - 1;
      }
      unsigned deleted = x2c_map_group_match(controls + start, 254) & lanes;
      if (available == ~0u && deleted)
        available = start + __builtin_ctz(deleted);
      unsigned empty = x2c_map_group_match(controls + start, 128) & lanes;
      if (empty) {
        (void) $value_valid(value);
        unsigned dead = *_deleted(map), capacity = map.capacity;
        if (map.used + dead >= (unsigned long) capacity * 3 / 4) {
          if (!dead || dead < capacity / 8) {
            if (capacity > ~0u / 2) raise %(size-limit (size $capacity));
            capacity *= 2;
          }
          if ($grow_tail)
            return map.grow_and_insert(key, value, inserted, capacity);
          _rebuild(map, capacity);
          goto retry;
        }
        if (available == ~0u) available = start + __builtin_ctz(empty);
        if (controls[available] == 254) (*_deleted(map))--;
        entries[available].key = *key;
        entries[available].val = *value;
        if ($side_hashes) full_hashes[available] = key_hash;
        else $remember_hash(&entries[available], key_hash);
        controls[available] = fingerprint;
        map.used++;
        *inserted = 1;
        return $value_at(map, available);
      }
      group = (group + step + 1) & group_mask;
    }
    (void) $insert_error(map.capacity);
  }

  static void $map.set_entry($map map, $key *key, $value *value) {
    int inserted;
    $value *stored = map.get_or_insert(key, value, &inserted);
    if (!inserted) *stored = *value;
  }

  static int $map.try_del_entry($map map, $key *key, $value *out) {
    if ((void *) map == NULL || !out) return 0;
    long index = map.find_index(key);
    if (index < 0) return 0;
    unsigned char *controls = map.hashes;
    $entry *entries = map.entries;
    *out = *$value_at(map, (unsigned) index);
    controls[index] = 254;
    entries[index] = ($entry) { 0 };
    map.used--;
    (*_deleted(map))++;
    return 1;
  }

  static int $map.try_next_entry(
    $map map, unsigned *cursor, $key *key, $value *value) {
    if ((void *) map == NULL || !cursor || !key || !value) return 0;
    unsigned char *controls = map.hashes;
    while (*cursor < map.capacity) {
      unsigned index = (*cursor)++;
      if (controls[index] < 128) {
        *key = *$key_at(map, index);
        *value = *$value_at(map, index);
        return 1;
      }
    }
    return 0;
  }
  static void _insert_all($map map, $map other) {
    unsigned cursor = 0;
    $key key;
    $value val;
    while (other.try_next_entry(&cursor, &key, &val))
      map.set_entry(&key, &val);
  }

  static $map $map.copy_entries($map map) {
    unsigned capacity = 2;
    if (map)
      while (map.used > (unsigned long) capacity * 3 / 4) capacity *= 2;
    $map copy = map.new_table(capacity), result = 0;
    defer if ((void *) result == 0) copy.free_table();
    _insert_all(copy, map);
    return result = copy;
  }

  static $map $map.merge_entries($map map, $map other) {
    if (!other) return map;
    int created = 0;
    if ((void *) map == 0) {
      map = map.new_table(2);
      created = 1;
    }
    $map result = 0;
    defer if (created && !result) map.free_table();
    _insert_all(map, other);
    return result = map;
  }

  static int $map.has_entries($map map) {
    return (void *) map != 0 && map.used != 0;
  }

  static int $map.equal_entries($map a, $map b) {
    if ((void *) a == (void *) b) return 1;
    if ((void *) a == 0 || (void *) b == 0) return 0;
    if (a.used != b.used) return 0;
    unsigned cursor = 0;
    $key key;
    $value avalue, bvalue;
    while (a.try_next_entry(&cursor, &key, &avalue))
      if (!b.try_get_entry(&key, &bvalue) ||
          !$value_equal(&avalue, &bvalue)) return 0;
    return 1;
  }
}

macro Unit $map.grouped.core.family(
  Type $family, Type $storage, Type $key, Type $value, Type $entry,
  Name $hash, Name $key_equal, Name $value_equal, Name $value_valid,
  Name $key_at, Name $value_at, Name $reinsert_error, Name $insert_error,
  Name $record_hash, Name $remember_hash, Literal $grow_tail,
  Literal $side_hashes
) {
  $map.grouped.storage.family(
    $family, $storage, $key, $value, $entry,
    $hash, $key_equal, $value_equal, $value_valid,
    $key_at, $value_at, $reinsert_error, $insert_error,
    $record_hash, $remember_hash, $grow_tail, $side_hashes, 1);
  $map.ownership.family($family);
}

macro Unit $map.grouped.typed.updates(
  Type $map, Type $key, Type $value, Name $update, Name $bad_arg,
  Name $bad_op, Name $value_at, Literal $one, Literal $postfix,
  Literal $owner
) {
  $value $map.updateindex($map, $key, Symbol, $value);
  $value $map.postfixindex($map, $key, Symbol);

  __attribute__((noinline)) static $value _update_other(
    $map map, $key key, Symbol op, $value rhs) {
    long index = map.find_index(&key);
    if (index < 0) (void) $bad_arg($owner);
    $value *stored = $value_at(map, (unsigned) index);
    return $update(stored, op, rhs);
  }

  /** Applies `op` to the value for `key` and returns the stored result.
      `+` inserts `rhs` when the key is absent; other operations require an
      existing key. Supported operations depend on the generated value type.
      Raises: `<bad-arg>` for a null map or missing required key, a cause from
      the generated value operation, or an allocation, size, or invariant cause
      while inserting. Invalid operations leave an existing value unchanged.
      Allocation and size failures leave the table unchanged.
  */
  $value $map.updateindex($map map, $key key, Symbol op, $value rhs) {
    if ((void *) map == 0) (void) $bad_arg($owner);
    if (op != <+>) return _update_other(map, key, op, rhs);
    int inserted;
    $value *stored = map.get_or_insert(&key, &rhs, &inserted);
    if (inserted) return rhs;
    return $update(stored, op, rhs);
  }

  /** Applies postfix `++` or `--` and returns the previous value.
      The key must already exist, and only generated numeric families support
      these operations.
      Raises: `<bad-arg>` for a null map or absent key, or `<bad-op>` for an
      unsupported operation. These failures leave the value unchanged.
  */
  $value $map.postfixindex($map map, $key key, Symbol op) {
    if ((void *) map == 0) (void) $bad_arg($owner);
    long index = map.find_index(&key);
    if (index < 0) (void) $bad_arg($owner);
    $value *stored = $value_at(map, (unsigned) index);
    $value old = stored[0];
    if (!$postfix) (void) $bad_op(op);
    if (op == <++>) $update(stored, <+>, $one);
    else if (op == <-->) $update(stored, <->, $one);
    else (void) $bad_op(op);
    return old;
  }

}

macro Unit $map.grouped.typed.family(Type $family, Type $key, Type $value,
  Name $update, Name $bad_arg, Name $bad_op, Name $capacity_valid,
  Name $value_at, Name $unbox, Literal $zero, Literal $one,
  Literal $postfix, Literal $owner) {
  $map.typed.operations(
    $family, $key, $value, $bad_arg, $capacity_valid, $zero, $owner, 0);
  $map.grouped.typed.updates(
    $family, $key, $value, $update, $bad_arg, $bad_op, $value_at,
    $one, $postfix, $owner);
  $map.typed.convert($family, $unbox);
}
