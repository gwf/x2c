/*  packages.x -- source collection packages

    Copyright (c) 2026 Gary William Flake.
*/

// package imports

/* One package's public surface while it is gathered: the package's name
   and root, the rows merged so far, the files already visited, and the
   token that locates errors. */
static typedef struct Surface {
  Compiler c, String name, root, Map merged, visited, Token token;
  Array exports;
} Surface;

/** Collects a package once and installs its public surface in the
    current unit.
    `name` resolves through the compiler's registered package roots. A cold
    entry include closure is parsed in package mode; cached entries replay
    their previously collected declarations. Public declarations and
    protocol rows enter the current symbol state, and dependencies enter the
    importing compiler. Replay also merges recorded function definitions.
    `token` locates lookup and public-surface errors.
*/
void Compiler.collect_package(Compiler c, String name, Token token) {
  if (name in c.package_roots) return;
  String root = NULL;
  String entry = _find_package(c, name, root, token);
  /* The root is registered before the walk, as a package unit's own is
     before its parse, so the walk can tell the package's files apart. */
  c.package_roots[name] = root;
  c.select_package_module(name, root, token);
  Compiler package = Compiler.new_shared(c);
  defer c.close_child(package);
  package.interface_provider = 1;
  package.package = name;
  package.filename = entry;
  _walk_package(c, package, entry, token);
  c.fn_defs.merge(package.fn_defs);
  Surface s = {
    .c = c, .name = name, .root = root, .merged = {}, .visited = {},
    .token = token, .exports = []};
  s.visited[entry] = 1;
  c.add_translation_dependency(entry);
  _gather_surface(s, entry, _process_cache()[entry]);
  _install(s);
  c.package_effects[name] = s.exports.list_free();
}

static String _find_package(
  Compiler c, String name, String &root, Token token) {
  String entry = c.sources.package_entry(c.package_dirs, name, root);
  if (entry) return entry;
  $fail.collect_package_unknown(c, token, name);
}

/* The package's files enter the cache from their entries, or from one cold
   walk in package mode. */
static void _walk_package(
  Compiler c, Compiler package, String entry, Token token) {
  Map globs = c.sym.base_symbols(), visited = {};
  visited[entry] = 1;
  List cached = _entry(package, entry);
  if (cached) {
    _replay_cached(package, cached, entry, globs, visited, NULL);
    return;
  }
  String text = NULL;
  if (!package.read_source(entry, text))
    $fail.collect_package_read(c, token, package, entry);
  _walk_apart(package, entry, text, globs, visited);
}

/* Replay each package include once and record its dependencies. */
static void _gather_surface(Surface &s, String path, List entry) {
  s.c.merge_translation_dependencies(entry[3]);
  foreach (Var part in entry.car())
    match ($(part)) {
      case %(?(Map rows)): _merge_surface(s, path, rows);
      case %(?(String include)): _include_surface(s, include);
      default: __builtin_unreachable();
    }
}

static void _include_surface(Surface &s, String path) {
  s.c.add_translation_dependency(path);
  if (path in s.visited) return;
  s.visited[path] = 1;
  _gather_surface(s, path, _process_cache()[path]);
}

/* The package's `name__` space is visible in the importing unit, and so is
   a C header or runtime module it publishes: a package renames what it
   declares, not what it includes, so those names cross as including that
   file gives them. Inside the package root an unprefixed x2c key is a
   static, which keeps C internal linkage and stays home; outside it the file
   escaped the declare-time rewrite and its bare names would merge into the
   consumer's one flat namespace. */
static void _merge_surface(Surface &s, String path, Map rows) {
  String prefix = %"$(s.name)__";
  int keeps = _keeps_spellings(path);
  int foreign = !path.startswith(%"$(s.root)/");
  Array exports = auto [];
  foreach (Var (key, value) in rows) {
    if (key is not <list> || key.is_nil()) continue;
    String spelling = _package_key_spelling(key);
    if (_package_protocol_row(key, value)) {
      // The prelude and earlier includes already supplied this source row.
      if (s.c.sym.get(key)) continue;
      _take(s, rows, key, value);
      if ($(key, value) ~=
          %(("source-node" (? ? ?position))
            (!set ?effect ((!or compile-time project-meta) *))))
        exports.push($(position, effect));
    }
    else if (spelling && (keeps || spelling.startswith(prefix)))
      _take(s, rows, key, value);
    else if (spelling && foreign) _reject(s, path, spelling);
  }
  exports.sort();
  foreach (List entry in exports) s.exports.push(entry.cadr());
}

static void _take(Surface &s, Map rows, List key, Var value) {
  s.merged[key] = value;
  s.c.copy_source_declaration(s.merged, rows, key);
}

static void _reject(Surface &s, String path, String spelling) {
  String name = s.name, unit = path.split("/").last();
  String fix = %"directly, or move it into '$name/src'";
  $fail.collect_package_prefix(s.c, s.token, name, spelling, unit, fix);
}

/* The merged rows enter the importing unit's symbols. */
static void _install(Surface &s) {
  foreach (List (key, value) in s.merged) {
    s.c.sym.set(key, value);
    s.c.copy_source_declaration(s.c.sym.current_symbols(), s.merged, key);
  }
}

/* A C header or a runtime module crosses with its own spellings. */
static int _keeps_spellings(String path) =>
  !Path.is_x2c_source(path) || _in_runtime(path);

module int _in_runtime(String path) =>
  path.startswith(%"$(_canonical_lib())/") ||
  path.startswith(%"$(_canonical_include())/");

/* A declaration key is a plain name, or a typedef or aggregate name that a
   member row may extend; the tag covers the whole family, so a member of a
   prefixed aggregate crosses with it. Source-node and helper rows carry no C
   spelling of their own. */
static String _package_key_spelling(List key) {
  match (key) {
    case %("function-inline" ?(String name)): return name;
    case %(?(String name)):
      return name == "source-node" || name == "source-typedef" ? NULL : name;
    case %(self ?(String name)): return name;
    case %((!or typedef struct union enum) ?(String name) *): return name;
  }
  return NULL;
}

/* Protocol declarations and adoptions are keyed by source location, and
   recorded conformances by base and participant, instead of by a spelling.
   A package's rows already name its own prefixed types, so they cross with
   the rest of its surface. */
static int _package_protocol_row(List key, Var value) {
  if (key.car() != "source-node" || value is not <list>) return 0;
  List row = value;
  return row && row.car() in
    %(protocol adopt meta-protocol conformance declaration-source
      native-meta compile-time project-meta meta-hashes interface-types
      native-object package-import);
}

// import replay

/* Replays package imports and public compile-time definitions in source
   order. The shadow borrows the unit's macro state and package registries.
   The unit's own definitions stay at their source sites. Provider
   collection replays active include-cycle prefixes; the full parse
   collects effects for the include line.
*/
module void _replay_package_imports(
  Compiler c, Map globs, Map rows, Array exports) {
  auto Array imports = NULL;
  foreach (Var (key, value) in rows)
    if (key ~= %("source-node" (? ?path ?position))) {
      if (value is not <list> || !value.list() ||
          !(value.list().car() in
            %(package-import compile-time project-meta))) continue;
      if ((exports == NULL && c.interface_provider) ||
          !_imported_here(c, path)) {
        if (!imports) imports = [];
        imports.push($(path, position, value));
      }
    }
  if (!imports.len()) return;
  imports.sort();
  _import_all(c, globs, imports, exports);
}

/* An import the unit itself wrote stays at its own source site. */
static int _imported_here(Compiler c, String path) =>
  _canonical_path(Compiler.absolute_home_path(path)) ==
    _canonical_path(c.filename);

/* The shadow reads the imports as a segment of the unit reads its own. */
static void _import_all(
  Compiler c, Map globs, Array imports, Array exports) {
  Compiler shadow = Compiler.new_shared(c);
  defer c.close_child(shadow);
  shadow.take_unit_state(c);
  shadow.builtin_defs = c.builtin_defs;
  shadow.sym.reset(globs);
  shadow.start_collection();
  foreach (List entry in imports)
    match (entry) {
      case %(?(String path) ?
             (package-import ?(String name) ?(String alias) ?members)):
        _import_package(shadow, path, name, alias, members, exports);
      case %(? ? (!set ?effect ((!or compile-time project-meta) *))):
        if (exports != NULL) exports.push(effect);
        else shadow.install_compile_time_effects($(effect));
    }
  shadow.return_unit_state(c);
  c.merge_translation_dependencies(shadow.deps);
}

static void _import_package(
  Compiler c, String path, String name, String alias, List members,
  Array effects) {
  c.filename = Compiler.absolute_home_path(path);
  c.collect_package(name, NULL);
  c.register_package_alias(name, alias, NULL);
  foreach (List member in members)
    c.register_package_member(name, member.car(), member.cadr(), NULL, NULL);
  if (effects != NULL)
    foreach (List effect in c.package_effects[name]) effects.push(effect);
  else c.install_compile_time_effects(c.package_effects[name]);
}
