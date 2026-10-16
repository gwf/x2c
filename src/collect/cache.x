/*  cache.x -- source collection cache

    Copyright (c) 2026 Gary William Flake.
*/

// the process cache

/* Process cache: canonical path ->
   `(ordered-parts hash definitions dependencies include-roots)`.
   A part is a declaration Map or an included source path. Dependencies
   map macro, Lisp, and embedded-text paths to a
   content hash or 1. Entries
   outlive per-unit scopes, so every retained key and value belongs to
   process_cache_scope. */
static Map process_cache = NULL;

module Map _process_cache(void) {
  if (process_cache != NULL) return process_cache;
  $scope(&process_cache_scope) {
    Scope.shutdown_hook(_cache_shutdown);
    process_cache = {};
  }
  return process_cache;
}

static void _cache_shutdown(void) {
  process_cache_scope.destroy();
  process_cache_scope = NULL;
  process_cache = NULL;
  provisional_entries = NULL;
  cold_providers = NULL;
  declared_functions = NULL;
  linked_records = NULL;
}

module Map _cache_map(void) {
  $scope(&process_cache_scope) return {};
}

module Map _cache_copy(Map map) {
  $scope(&process_cache_scope) return map.copy();
}

/* A file's entry: collected in this process, or read from its interface. */
module List _entry(Compiler c, String canonical) {
  Var cached = _process_cache()[canonical];
  if (cached is <list>) {
    if (List.equal(cached.list()[4], _interface_include_dirs(c, canonical)))
      return cached;
    (void) _process_cache().del(canonical);
  }
  return _interface_read(c, canonical);
}

/* Native declaration calls can change provider state. Only their cold walk
   reproduces both the signatures and effects in the provider's own session. */
module List _collection_entry(Compiler c, String path) {
  List entry = _entry(c, path);
  if (!entry || path in c.collection_native_files) return entry;
  foreach (Var part, entry.car())
    if (part is <map> && %("collection-native") in part.map()) {
      _process_cache().del(path);
      return NULL;
    }
  return entry;
}

module String _content_hash(String text) => "%08x".printf(text.hash());

module void _cache_dependency(Map dependencies, String path, Var hash) {
  _retain(path);
  _retain(hash);
  dependencies.merge_translation_dependency(path, hash);
}

module void _cache_dependencies(Map dependencies, Map additions) {
  foreach (Var (path, hash), additions)
    _cache_dependency(dependencies, path, hash);
}

/* A value the cache keeps must be owned beyond every unit's pools. */
module void _retain(Var value) {
  if (value is <list>) _require_retained(value.list().try_own());
  if (value is <string>) _require_retained(value.string().try_own());
}

module void _require_retained(int owned) {
  if (owned) return;
  fprintf(stderr, "x2c: could not retain process cache entry\n");
  abort();
}

/* Unresolvable paths retain the caller's spelling. This is
   `Compiler.canonical_path` without a source view: an unsaved file keeps
   the spelling the include search built, which keys its process-cache
   entry, and `SourceView.resolve_include` searches with no Compiler. */
module String _canonical_path(String path) {
  String real = Path.real(path);
  return real ? real : path;
}

/* Canonical process-wide include roots. */
static String _cached_canonical(char *cache, String dir) {
  if (!*cache && !realpath(dir, cache))
    snprintf(cache, PATH_MAX, "%s", (char *) dir);
  return cache;
}

module String _canonical_lib(void) {
  static char cache[PATH_MAX];
  if (*cache) return cache;
  return _cached_canonical(cache, %"${x2c_get_root()}/lib");
}

module String _canonical_include(void) {
  static char cache[PATH_MAX];
  if (*cache) return cache;
  return _cached_canonical(cache, %"${x2c_get_root()}/include/x2c");
}

module String _canonical_src(void) {
  static char cache[PATH_MAX];
  if (*cache) return cache;
  return _cached_canonical(cache, %"${x2c_get_root()}/src");
}

module String _canonical_cwd(void) {
  static char cache[PATH_MAX];
  return _cached_canonical(cache, ".");
}

module void _retain_rows(List parts) {
  foreach (Var part, parts) {
    if (part is not <map>) continue;
    foreach (Var (key, value), part.map()) {
      _retain(key);
      _retain(value);
    }
  }
}

// cache lifecycle

/** Makes the next collection recheck source files and interfaces after an
    interactive edit. Drops cache indexes, retaining their backing rows:
    already-open units may still use those declarations. */
void Compiler.refresh_source_collections(void) {
  _reset_cache(process_cache);
  _reset_cache(provisional_entries);
  _reset_cache(cold_providers);
  _reset_cache(declared_functions);
  _reset_cache(source_hashes);
  _reset_cache(linked_providers);
}

static void _reset_cache(Map &cache) {
  if (!cache) return;
  cache.cleanup();
  cache = _cache_map();
}

/** Drops the entries collected without declaration defaults while the shared
    compile-time session was filled, or by a project meta build. Call once
    that session is published, and after the meta build's parses. */
void Compiler.forget_provisional_entries(void) {
  if (!provisional_entries) return;
  foreach (Var path, provisional_entries.keys())
    (void) _process_cache().del(path);
  provisional_entries = NULL;
}
