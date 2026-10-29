/*  root-index.x -- append-only index for process-root canonical values

    A published hash commits one immutable value. Entries never move within
    an index; growth publishes a replacement and leaves every older version
    in the root Scope until quiescent shutdown. Writers hold the root mutex.
    Native String/List readers need only acquire loads. Other key kinds keep
    their existing callback serialization under the recursive root mutex.
*/

static keyword loop $private.loop;

static PoolTable root_index;

module void _root_initialize(PoolTable table) {
  __atomic_store_n(&root_index, table, __ATOMIC_RELEASE);
}

module int _root_native(Var key) =>
  (void *) key.string_payload() != NULL || (void *) key.list_payload() != NULL;

module String _root_string(const char *bytes, int length, unsigned hash) {
  PoolTable table = __atomic_load_n(&root_index, __ATOMIC_ACQUIRE);
  Var *entries = table.entries;
  unsigned *hashes = table.hashes, mask = table.mask;
  for (unsigned distance = 0; distance < table.capacity; distance++) {
    unsigned index = (hash + distance) & mask;
    unsigned stored = __atomic_load_n(&hashes[index], __ATOMIC_ACQUIRE);
    if (!stored) return NULL;
    if (stored == hash) {
      Var entry = entries[index];
      String string = entry.string_payload();
      if (string && string.len() == length && !memcmp(string, bytes, length))
        return string;
    }
  }
  return NULL;
}

module Var _root_lookup(Var key, unsigned hash) {
  PoolTable table = __atomic_load_n(&root_index, __ATOMIC_ACQUIRE);
  return _root_find(table, key, hash);
}

/* The caller either holds the root lock or supplies a native String/List
   query. Those kinds never invoke custom equality, including on collisions
   with a different kind. Readers do not inspect the writer's used count. */
static Var _root_find(PoolTable table, Var key, unsigned hash) {
  Var *entries = table.entries;
  unsigned *hashes = table.hashes, mask = table.mask;
  for (unsigned distance = 0; distance < table.capacity; distance++) {
    unsigned index = (hash + distance) & mask;
    unsigned stored = __atomic_load_n(&hashes[index], __ATOMIC_ACQUIRE);
    if (!stored) return void;
    if (stored == hash) {
      Var entry = entries[index];
      if (_root_key_equal(entry, key)) return entry;
    }
  }
  return void;
}

module Var _root_intern(Var object, int &inserted) {
  unsigned hash = object.hash();
  loop {
    PoolTable table = value_root.table;
    Var found = _root_find(table, object, hash);
    if (found is not void) { inserted = 0; return found; }
    // A custom equality callback may have grown the root recursively.
    if (table != value_root.table) continue;
    if (table.used >= table.capacity / 2 + table.capacity / 4)
      table = _root_grow(table);
    _root_append(table, object, hash);
    inserted = 1;
    return object;
  }
}

static PoolTable _root_grow(PoolTable previous) {
  if (previous.capacity > ~0u / 2)
    raise %(size-limit (operation "Pool root index") (size $(previous.capacity)));
  Scope version = Scope.new();
  int retained = 0;
  defer if (!retained) version.destroy();
  PoolTable table;
  auto (&version)
    table = _root_new_table(previous.capacity * 2);
  unsigned *hashes = previous.hashes;
  Var *entries = previous.entries;
  for (unsigned i = 0; i < previous.capacity; i++) {
    unsigned hash = __atomic_load_n(&hashes[i], __ATOMIC_ACQUIRE);
    if (hash) _root_append(table, entries[i], hash);
  }
  version.transfer(value_root.scope);
  retained = 1;
  value_root.table = table;
  _root_initialize(table);
  return table;
}

static void _root_append(PoolTable table, Var object, unsigned hash) {
  unsigned *hashes = table.hashes, index = hash & table.mask;
  Var *entries = table.entries;
  while (__atomic_load_n(&hashes[index], __ATOMIC_ACQUIRE))
    index = (index + 1) & table.mask;
  entries[index] = object;
  __atomic_store_n(&hashes[index], hash, __ATOMIC_RELEASE);
  table.used++;
}
