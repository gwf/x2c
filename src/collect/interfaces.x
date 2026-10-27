/*  interfaces.x -- source collection interfaces

    Copyright (c) 2026 Gary William Flake.
*/

// unit interfaces

/* A `.xi` interface is one unit's cache entry written beside its generated
   C. It records the identity of the compiler that wrote it, because a
   different compiler may collect different rows from the same source.
   Missing, stale, foreign, or malformed interfaces are cache misses; the
   caller walks the file cold and installs that result in the process cache.
   Paths inside an interface use `Compiler.portable_path` spellings. */

static String interface_out_dir = NULL;

static String interface_mirror = NULL;

/** Creates the process cache and names the directories searched for `.xi`
    interfaces. `out_dir` is the current translation output directory, or
    NULL. Home files mirror their home-relative path under the compiler's
    stage directory when it runs from `<home>/builds/`, otherwise under the
    home. A `cold` process reads no interface and still writes its own. Call
    it before opening any translation unit's Context.
*/
void Compiler.configure_interfaces(String out_dir, int cold) {
  _process_cache();
  interface_out_dir = out_dir;
  String stage = Compiler.stage_dir();
  if (cold) interface_mirror = NULL;
  else interface_mirror = stage ? stage : x2c_get_root();
}

/* Find and validate the interface of one canonical source path: the
   record linked into the compiler for a prelude component, else its `.xi`.
   A source under inspection through a SourceView, or a cold process, reads
   neither. */
module List _interface_read(Compiler c, String canonical) {
  if (c.source_facts || !interface_mirror) return NULL;
  List record = _linked_record(canonical);
  if (record) {
    List entry = _stored_entry(c, canonical, record);
    if (entry) return entry;
  }
  foreach (String path in _interface_candidates(canonical)) {
    List entry = _interface_load(c, canonical, path);
    if (entry) return entry;
  }
  return NULL;
}

/* Candidate interface paths for one canonical source path: the output
   directory by stem, its sibling that mirrors a home file's directory, the
   home mirror, and a package's `builds/` beside or above the source. A
   stage batch keeps its artifacts flat under its area, so a home file in a
   subdirectory, such as a runtime module unit, is also sought at the
   mirror of each enclosing home directory. */
static List _interface_candidates(String canonical) {
  String stem = Path.stem(canonical);
  String relative = Compiler.portable_path(canonical);
  String dir = Path.dirname(canonical), Array paths = [];
  if (interface_out_dir) paths.push(%"$interface_out_dir/$stem.xi");
  if (relative != canonical)
    for (String home = Path.dirname(relative); home != ".";
         home = Path.dirname(home)) {
      String mirror = %"$home/$stem.xi";
      if (interface_out_dir) paths.push(%"$interface_out_dir/../$mirror");
      paths.push(%"$interface_mirror/$mirror");
    }
  paths.push(%"$dir/builds/$stem.xi");
  paths.push(%"$dir/../builds/$stem.xi");
  return paths.list_free();
}

/* Materialize one interface file only after its compiler identity, source
   path and hash, and the content hashes of the includes, macros, and
   embedded text it depends on, validate. The entry uses process_cache_scope
   ownership and the same ordered parts representation as a cold walk. */
static List _interface_load(Compiler c, String canonical, String path) {
  String identity = Compiler.identity();
  if (_interface_record(path) ~= %(interface 6 ?(String compiler) *stored) &&
      identity && compiler == identity)
    return _stored_entry(c, canonical, stored);
  return NULL;
}

/* The entry of a stored record whose source, hash, and include roots still
   match `canonical`, or NULL. */
static List _stored_entry(Compiler c, String canonical, List stored) {
  if (stored ~= %(?(String owner) ?(String hash) ?(List parts)
      ?(List definitions) ?(List dependencies) ?(List include_dirs)) &&
      Compiler.absolute_home_path(owner) == canonical &&
      _hash_matches(c, canonical, hash) &&
      _interface_include_dirs(c, canonical) == include_dirs)
    return _interface_entry(
      c, canonical, hash, parts, definitions, dependencies, include_dirs);
  return NULL;
}

/* The file's one List form, or NULL when it is missing or unreadable. */
static List _interface_record(String path) {
  File input = fopen(path, "r");
  if (!input) return NULL;
  String source = NULL;
  try source = input.string_close();
  catch %(io-fail *): return NULL;
  String identity = Compiler.identity();
  if (!identity || !source.startswith(%"(interface 6 \"$identity\" "))
    return NULL;
  return _read_record(source);
}

/* The one List form `source` spells, or NULL. */
static List _read_record(String source) {
  unsigned cursor = 0, Var record = void, int read = 0;
  try read = (source.read_lisp_form(cursor, record) == <value>);
  catch %((!or incomplete malformed) *): return NULL;
  if (!read || record is not <list>) return NULL;
  return record;
}

module int _hash_matches(Compiler c, String path, Var expected) {
  if (expected is not <string>) return 0;
  String hash = String.startswith(expected, "search:") ?
    _include_search_hash(c, path) : _source_hash(c, path);
  return hash && String.equal(hash, expected);
}

/* NULL when the source cannot be read. */
static String _source_hash(Compiler c, String path) {
  Var cached = source_hashes[path];
  if (cached is not void) return cached;
  String text = NULL;
  try {
    if (!c.read_source(path, text)) return NULL;
  }
  catch %((!or io-fail bad-arg size-limit) *): return NULL;
  String hash = _content_hash(text);
  _retain(path);
  _retain(hash);
  source_hashes[path] = hash;
  return hash;
}

/* Rebuild a validated interface's rows as a process cache entry, or return
   NULL when a row is malformed or a dependency has changed. */
static List _interface_entry(
  Compiler c, String canonical, String hash, List stored_parts,
  List definitions, List stored_dependencies, List include_dirs) {
  Array parts = [];
  if (!_read_parts(parts, stored_parts)) return NULL;
  Map dependencies = _read_dependencies(c, stored_dependencies);
  if (dependencies == NULL) return NULL;
  foreach (Var definition in definitions)
    if (definition is not <string>) return NULL;
  List entry = $(
    parts.list_free(), hash, definitions, dependencies, include_dirs);
  _retain(canonical);
  _require_retained(entry.try_own());
  _process_cache()[canonical] = entry;
  return entry;
}

/* A stored part is an include path or a list of rows. */
static int _read_parts(Array parts, List stored) {
  foreach (Var part in stored) {
    if (part is <string>)
      parts.push(_canonical_path(Compiler.absolute_home_path(part)));
    else if (part is not <list>) return 0;
    else {
      Map rows = _read_rows(part);
      if (rows == NULL) return 0;
      parts.push(rows);
    }
  }
  return 1;
}

/* A stored row is a two-element list of key and value. */
static Map _read_rows(List stored) {
  Map rows = _cache_map();
  foreach (Var row in stored) {
    if (row is not <list> || row.list().len() != 2) return NULL;
    List pair = row;
    _require_retained(pair.try_own());
    Var (key, value) = pair;
    /* The List pattern itself rejects other value tags. */
    if (value ~= %(meta-hashes ?provider ?(List stored))) {
      Map hashes = _read_rows(stored);
      if (hashes == NULL) return NULL;
      value = %(meta-hashes $provider $hashes);
      _retain(value);
    }
    rows[key] = value;
  }
  return rows;
}

/* Each dependency still hashes as it did when the interface was written; a
   hash of 1 marks a file that is not hashed. */
module Map _read_dependencies(Compiler c, List stored) {
  Map dependencies = _cache_map();
  foreach (Var dependency in stored) {
    if (dependency is not <list>) return NULL;
    if (dependency.list() ~= %(?(String name) ?hash)) {
      String path = name;
      if (hash is <string> && String.startswith(hash, "search:")) {
        if (!name.startswith("cwd:"))
          path = Compiler.absolute_home_path(name);
      }
      else path = _canonical_path(Compiler.absolute_home_path(name));
      int unhashed = hash.is_integer() && hash.integer() == 1;
      if (!unhashed && !_hash_matches(c, path, hash)) return NULL;
      _cache_dependency(dependencies, path, hash);
      continue;
    }
    return NULL;
  }
  return dependencies;
}

/** Returns the path of the first prelude interface this compiler wrote, or
    NULL when there is none or the compiler's identity is unknown. Its
    source hashes are not checked.
*/
String Compiler.prelude_interface(void) =>
  _written_interface(_canonical_path(%"$(x2c_get_root())/lib/x2c.x"));

/** Returns the home-relative paths of the runtime units the prelude
    interface includes whose own interface this compiler did not write, or
    NULL when every one is present or there is no prelude interface. A
    missing interface walks that unit cold in every process, so a converged
    stage build reports none.
*/
List Compiler.prelude_missing_interfaces(void) {
  String prelude = Compiler.prelude_interface();
  List record = prelude ? _interface_record(prelude) : NULL;
  Array missing = [];
  if (record ~= %(interface 6 ? ? ? ?(List parts) *))
    foreach (Var part in parts)
      if (part is <string> &&
          !_written_interface(Compiler.absolute_home_path(part)))
        missing.push(part);
  return missing.list_free();
}

/* The first candidate interface of `canonical` that this compiler wrote,
   or NULL. Only the identity header is checked. */
static String _written_interface(String canonical) {
  String identity = Compiler.identity();
  if (!identity) return NULL;
  String header = %"(interface 6 \"$identity\" ";
  foreach (String path in _interface_candidates(canonical)) {
    String text = NULL;
    try text = Path.read_text(path);
    catch %((!or not-found io-fail) *): continue;
    if (text.startswith(header)) return path;
  }
  return NULL;
}

// writing interfaces

/** Returns the compiler's own collected contribution as interface text, or
    NULL when the unit has not collected its symbols or the compiler's
    identity is unknown, since no compiler could replay that interface. A
    contribution that the interface grammar cannot spell is reported as an
    `emit` diagnostic.
*/
String Compiler.interface_text(Compiler c) {
  if (!Compiler.identity()) return NULL;
  String canonical = _canonical_path(c.filename);
  Var cached = _process_cache()[canonical];
  if (cached is void) return NULL;
  Buffer out = auto Buffer.new(0);
  List record = %(
    interface 6 $(Compiler.identity()) @(_stored_record(canonical, cached)));
  /* An interface is plain data, which a loader never evaluates. */
  if (!out.write_datum(record, 0)) $fail.collect_interface_write(c, NULL);
  out.write_char('\n');
  return out;
}

/* An entry as an interface stores it after the compiler identity. */
static List _stored_record(String canonical, List entry) {
  (List cached_parts, Var hash, List definitions, Map dependencies,
   List include_dirs) = entry;
  Map identities = {}, Array parts = [];
  foreach (Var part in cached_parts)
    parts.push(_stored_part(part, identities));
  return $(
    Compiler.portable_path(canonical), hash, parts.list_free(), definitions,
    _stored_dependencies(dependencies), include_dirs);
}

/* Search roots and the file's package mode must match before replay. */
module List _interface_include_dirs(Compiler c, String canonical) {
  Array dirs = [];
  foreach (String dir in c.include_dirs) {
    String portable = Compiler.portable_path(dir), List row = NULL;
    if (dir == x2c_get_root()) row = %(home "");
    else if (portable != dir) row = %(home $portable);
    else row = dir.startswith("/") ? %(absolute $dir) : %(relative $dir);
    dirs.push(row);
  }
  String root = Compiler.package_directory(c.package_source_dirs, canonical);
  String package = NULL;
  if (root && Compiler.is_package_source(root, canonical))
    package = Path.basename(root);
  else if (c.owns_package_source(canonical)) package = c.package;
  int source = Path.is_x2c_source(canonical);
  dirs.push(source && package ? %(package $package) : %(package));
  return dirs.list_free();
}

/* A stored part is a home-portable include path or the sorted rows of a
   declaration map with bindings renumbered. */
static Var _stored_part(Var part, Map identities) {
  if (part is not <map>) return Compiler.portable_path(part);
  Array rows = [];
  foreach (Var (key, value) in part.map()) rows.push($(key, value));
  rows.sort();
  return _renumber_bindings(rows.list_free(), identities);
}

module List _stored_dependencies(Map dependencies) {
  Array rows = [];
  foreach ((String path, Var hash) in dependencies)
    rows.push($(Compiler.portable_path(path), hash));
  rows.sort();
  return rows.list_free();
}

module List _stored_meta_hashes(Map hashes) {
  Array rows = [];
  foreach (String (spelling, hash) in hashes) rows.push($(spelling, hash));
  rows.sort();
  return rows.list_free();
}

/* A cold walk numbers bindings from wherever the shared counter stands, which
   depends on the files walked before it. An interface renumbers them in order
   of first appearance, keeping equal bindings equal. */
static List _renumber_bindings(List node, Map identities) {
  if (node ~= %(meta-hashes ?provider ?(Map hashes)))
    return %(meta-hashes $provider $(_stored_meta_hashes(hashes)));
  String spelling = NULL;
  if (Ast.try_binding(node, NULL, spelling)) {
    Var identity = identities.setdefault(node, identities.len() + 1);
    return Ast.binding(identity, spelling);
  }
  Var child;
  $ast.rewrite_children(node, child, _renumber_bindings(child, identities));
}

// linked prelude

/** Returns the interface record text of each prelude component the
    compiler links, by home-portable path: the datum its `.xi` holds after
    the compiler identity. Each is walked cold by a compiler of its own, so
    the records hold this compiler's collection rather than a table linked
    into it; the unit's own entries for them are restored afterwards. A
    record the interface grammar cannot spell is left out.
*/
Map Compiler.linked_prelude_records(Compiler c) {
  Map records = {}, saved = {};
  foreach (String source in _linked_prelude_sources()) {
    String canonical = _canonical_path(%"$(x2c_get_root())/$source");
    saved[canonical] = _process_cache()[canonical];
    (void) _process_cache().del(canonical);
  }
  Compiler walker = Compiler.new();
  walker.sources = c.sources;
  walker.include_dirs = c.include_dirs;
  walker.filename = c.filename;
  with (interface_mirror = NULL) {
    foreach (String source in _linked_prelude_sources()) {
      String path = %"$(x2c_get_root())/$source";
      String canonical = _canonical_path(path);
      Map visited = {};
      visited[canonical] = 1;
      _walk_apart(walker, canonical, _runtime_text(walker, path), {}, visited);
      String text = _record_text(
        _stored_record(canonical, _process_cache()[canonical]));
      if (text) records[Compiler.portable_path(canonical)] = text;
    }
  }
  foreach ((String canonical, Var entry) in saved)
    if (entry is <list>) _process_cache()[canonical] = entry;
  return records;
}

/* The record linked for `canonical`, read as its interface would be, or
   NULL. */
static List _linked_record(String canonical) {
  if (!linked_records) {
    _process_cache();
    auto (&process_cache_scope) linked_records = $_x2c_prelude_records();
  }
  Var text;
  if (!linked_records.try_get(Compiler.portable_path(canonical), text))
    return NULL;
  return _read_record(text);
}

/* Every prelude source but `lib/x2c.x`, whose interface stays a file. */
static List _linked_prelude_sources(void) => Compiler.prelude_sources().cdr();

/* `record` as an interface spells it, or NULL when it cannot be spelled. */
static String _record_text(List record) {
  Buffer out = auto Buffer.new(0);
  if (out.write_datum(record, 0)) return out;
  return NULL;
}
