/*  declarations.x -- source collection declarations

    Copyright (c) 2026 Gary William Flake.
*/

/* Type rows keep their complete family: the tag, its fields and field
   order, or a typedef and its ordinary-name row. A public declaration can
   require an otherwise static family, including through an alias chain. */
module List _type_family(List key) {
  match (key) {
    case %((!set ?kind (!or typedef struct union enum)) ?name *):
      return %($kind $name);
  }
  return NULL;
}

static List _row_type_family(Map rows, Map statics, List key, Var value) {
  List family = _type_family(key);
  if (family) return family;
  match (key) case %(?(String name)):
    if (%(typedef $name) in rows) return %(typedef $name);
  if (!(key in statics) && value is <list>) {
    Type type = value;
    if (type.is_enum()) return _type_family(type.base_type());
  }
  return NULL;
}

static int _private_row(Map statics, List key, List family) {
  if (family && family in statics) return 1;
  match (key) case %(self ?name): return %(function $name) in statics;
  return key in statics;
}

/* Only names that this file declares are candidates. Includes already
   contribute their selected interface at their recorded source position. */
module void _needed_types(List syntax, Map rows, Map needed) {
  Array pending = $auto([syntax]);
  while (pending.len()) {
    Var item = pending.take_last();
    if (item is not <list>) continue;
    match (item)
      case %((!or declare typedef function) ?base *)
        if (base.type().is_static()): continue;
    match (item) case %(adopt ? ? static *): continue;
    match (item) case %(declaration-function ?declaration *): {
      if (!declaration.list().type_from_ast().is_static())
        pending.push(declaration);
      continue;
    }
    List type = item;
    while (type.car() is <symbol> &&
           (type.car().symbol().is_type_qualifier() ||
            type.car().symbol().is_storage_class())) type = type.cdr();
    List family = _type_family(type);
    if (family && family in rows) needed[family] = 1;
    /* A typedef spelling is needed through any declarator. Aggregate
       completeness remains attached to the direct tag demand above. */
    Type base = type.type().base_type();
    match (base) case %(?(String name)):
      if (%(typedef $name) in rows) needed[%(typedef $name)] = 1;
    foreach (Var part in item) pending.push(part);
  }
}

module void _select_public(FileWalk &w) {
  if (!w.unit) return;
  Map rows = {}, needed = {}, selected = {};
  foreach (Var part in w.parts) if (part is <map>) rows.merge(part);
  foreach (Var (key, value) in rows) {
    // The owning unit replays its recipes before its Context closes.
    match (value) case %(declaration-source *): continue;
    List family = _row_type_family(rows, w.statics, key, value);
    if (_private_row(w.statics, key, family)) continue;
    selected[key] = 1;
    if (family) needed[family] = 1;
    if (value is <list>) _needed_types(value, rows, needed);
  }
  int changed;
  do {
    changed = 0;
    foreach (Var (key, value) in rows) {
      List family = _row_type_family(rows, w.statics, key, value);
      if (!family || !(family in needed) || key in selected) continue;
      selected[key] = 1;
      if (value is <list>) _needed_types(value, rows, needed);
      changed = 1;
    }
  } while (changed);
  foreach (Var part in w.parts) {
    if (part is not <map>) continue;
    Array dropped = $auto([]);
    foreach (Var key in part.map().keys())
      if (!(key in selected)) dropped.push(key);
    foreach (Var key in dropped) part.map().del(key);
  }
}

/* A `static` function belongs to the file that defines it, so its
   declaration row never crosses an include.
   The published marker names the defining file, which lets an including unit
   report a reference to the name instead of emitting a prototype that no
   object defines. The file is spelled home-portably, as interfaces spell
   paths. Only `.x` units publish markers; a C header's static inline
   functions belong to every file that includes it. */
module void _publish_unit_statics(Map statics, Map overlay, String path) {
  List owner = %(${Compiler.portable_path(path)});
  foreach (List key in statics.keys())
    match (%($key)) case %((function ?(String name))): {
      overlay.del(%($name));
      overlay.del(%(self $name));
      overlay[%("unit-static" $name)] = owner;
    }
}

/** The typedef names published by the files that the current unit's
    include of `target` reaches, including its transitive includes.
    A file already in `seen`
    is skipped with the files it reaches, and each file reached is added to
    `seen`. NULL when the include does not resolve to x2c source; a runtime
    module adds nothing the prelude has not declared. */
List Compiler.include_typedef_names(
  Compiler c, String target, int angle, Map seen) {
  String path = c.sources.resolve_include(
    c.include_dirs, Path.dirname(c.filename), target, angle);
  if (!path || !Path.is_x2c_source(path)) return NULL;
  Array names = [];
  _add_typedef_names(c, names, _canonical_path(path), seen);
  return names.list_free();
}

/** The semantic type rows reached by an ordinary source include. Each
    file contributes once to `seen`; the current unit does not contribute
    through a cycle back to its own still-open header. */
List Compiler.include_type_dependencies(
  Compiler c, String target, int angle, Map seen) {
  String path = c.sources.resolve_include(
    c.include_dirs, Path.dirname(c.filename), target, angle);
  if (!path || !Path.is_x2c_source(path)) return NULL;
  seen[_canonical_path(c.filename)] = 1;
  Array types = [];
  _add_type_dependencies(c, types, _canonical_path(path), seen);
  return types.list_free();
}

static void _add_type_dependencies(
  Compiler c, Array types, String path, Map seen) {
  if (path in seen) return;
  seen[path] = 1;
  List entry = _entry(c, path);
  if (!entry) return;
  foreach (Var part in entry.car())
    match (%($part)) {
      case %(?(Map rows)):
        foreach (Var (key, value) in rows) {
          if (value is not <list> ||
              (!_type_family(key) && key.list().cdr())) continue;
          List item;
          $ast.walk(value, item) {
            Type base = item.type().base_type();
            if (base.is_bare_typedef_name()) types.push(base);
          }
        }
      case %(?(String include)):
        _add_type_dependencies(c, types, include, seen);
    }
}

/** Adds the public functions an included unit itself declares. Its collected
    include closure also contains private source includes, which its generated
    header need not publish. Those cannot supply declarations here. Meta
    signatures alone do not establish a runtime declaration either. Emission
    reads the entries collection already installed without invalidating
    them. */
void Compiler.include_function_declarations(
  Compiler c, String target, int angle, Map available) {
  String path = c.sources.resolve_include(
    c.include_dirs, Path.dirname(c.filename), target, angle);
  if (path) _add_function_declarations(c, _canonical_path(path), available);
}

/** The runtime umbrella includes each listed module's generated header.
    Compiler components in the semantic prelude supply no runtime header. */
void Compiler.runtime_function_declarations(Compiler c, Map available) {
  String path = _canonical_path(%"${x2c_get_root()}/lib/x2c.x");
  Var entry = _process_cache()[path];
  if (entry is not <list>) return;
  foreach (Var part in entry.list().car())
    if (part is <string>) _add_function_declarations(c, part, available);
}

/** Returns the one-part names that the source at home-relative `path`
    declares itself, without its includes, as this process collected it.
    A source this process has not collected declares no names. */
List Compiler.collected_names(String path) {
  String canonical = _canonical_path(Compiler.absolute_home_path(path));
  Var entry = _process_cache()[canonical];
  if (entry is not <list>) return NULL;
  Array names = [];
  foreach (Var part in entry.list().car())
    if (part is <map>)
      foreach (Var key in part.map().keys())
        match (key) case %(?(String name)): names.push(name);
  return names.list_free();
}

static void _add_function_declarations(
  Compiler c, String path, Map available) {
  if (path == _canonical_path(c.filename)) return;
  Var entry = _process_cache()[path];
  if (entry is not <list>) return;
  foreach (String name in _declared_functions(entry))
    if (!(name in c.meta_comptime) && !(name in c.project_meta))
      available[%(native $name)] = 1;
}

/* The function names an entry's rows declare, read once per entry. */
static Array _declared_functions(List entry) {
  if (!declared_functions) declared_functions = _cache_map();
  Var cached = declared_functions[entry];
  if (cached is <array>) return cached;
  $scope(&process_cache_scope) {
    Array names = [];
    foreach (Var part in entry.car()) {
      if (part is not <map>) continue;
      foreach (Var (key, value) in part.map())
        match (key) case %(?(String name))
          if (value is <list> && value.list().type().is_function()):
            names.push(name);
    }
    declared_functions[entry] = names;
    return names;
  }
}

/** Reports whether this unit's selected interface publishes `name`. */
int Compiler.publishes_typedef(Compiler c, String name) {
  return c.publishes_type_family(%(typedef $name));
}

/** Reports whether this unit's interface publishes the type `family`. */
int Compiler.publishes_type_family(Compiler c, List family) {
  List entry = _entry(c, _canonical_path(c.filename));
  if (!entry) return 0;
  foreach (Var part in entry.car())
    if (part is <map> && family in part.map()) return 1;
  return 0;
}

static void _add_typedef_names(
  Compiler c, Array names, String path, Map seen) {
  if (path in seen || _in_runtime(path)) return;
  seen[path] = 1;
  List entry = _entry(c, path);
  if (entry)
    foreach (Var part in entry.car())
      match (%($part)) {
        case %(?(Map rows)):
          foreach (Var key in rows.keys())
            match (%($key)) case %((typedef ?(String name))):
              names.push(name);
        case %(?(String include)):
          _add_typedef_names(c, names, include, seen);
      }
}

/* Each provider binds its header bodies in its own original session.
   Included signatures come from the completed graph; effects still install
   at the provider's ordinary include positions. Remove the work before
   replay, because a cold dependency can complete more pending providers. */
module void _bind_pending_inline_bodies(
  Compiler c, Map globs, String unit) {
  Array pending = c.pending_inline_bodies;
  if (!pending.len()) return;
  while (pending.len()) {
    (Compiler body, String path, String text, Map symbols, Map own,
     Map statics, Map hashes, Var markers) = pending.shift();
    Map visited = {};
    visited[path] = 1;
    Array effects = [];
    _replay_cached(
      body, _entry(body, path), path, symbols, visited, effects);
    body.filename = path;
    body.meta_hashes = hashes;
    body.tokenize(text);
    if (markers is not void) body.line_markers = markers;
    List ast = body.full_parse(symbols, 0);
    _retain_rows(%($hashes));
    Map additions = _inline_type_dependencies(body, ast);
    _publish_inline_dependencies(body, path, own, statics, additions);
    foreach (Var part in _entry(body, path).car())
      if (part is <map>) _merge_rows(c, globs, part);
    c.merge_translation_dependencies(body.deps);
    body.public_bodies = 0;
    c.close_child(body);
  }
  Map visited = {};
  visited[unit] = 1;
  Array effects = [];
  List entry = _entry(c, unit);
  if (!entry) return;
  _replay_cached(c, entry, unit, globs, visited, effects);
  _forget_own_statics(globs, entry);
}

/* A unit's entry marks its static functions for the units that include it.
   The unit's own walk keeps those markers out of its symbols. */
static void _forget_own_statics(Map globs, List entry) {
  foreach (Var part in entry.car())
    if (part is <map>)
      foreach (Var key in part.map().keys())
        match (key) case %("unit-static" ?): globs.del(key);
}

module int _declares_adoption(List parts) {
  foreach (Var part in parts)
    if (part is <map>)
      foreach (Var value in part.map())
        match (value) case %(adopt ? ? external *): return 1;
  return 0;
}

/* The declarations and definitions gathered from a set of files' entries,
   and the files gathered. */
static typedef struct Gathered {
  Map symbols, definitions, visited;
} Gathered;

/* The compilers that resolve cold files' adoptions for one unit. A file in
   the prelude sees only the prelude, so one compiler resolves every such
   file; any other file gets a compiler of its own. */
static typedef struct ColdConformances {
  Compiler c, prelude_session;
  Gathered prelude;
} ColdConformances;

/* A file collected cold records the conformances it declares as its own
   translation does, so a unit that includes it reuses the same answer
   whether or not the file's interface was current. The file's own unit
   records them when it translates. */
module void _record_cold_conformances(
  Compiler c, Map globs, Map visited, String unit) {
  ColdConformances cold = {.c = c};
  defer if (cold.prelude_session) c.close_child(cold.prelude_session);
  while (cold_providers) {
    Map pending = cold_providers;
    cold_providers = NULL;
    foreach (String path in pending.keys()) {
      if (path == unit) continue;
      Map rows = _record(cold, path);
      if (path in visited) _merge_rows(c, globs, rows);
    }
  }
}

static Map _record(ColdConformances &cold, String path) {
  if (!cold.prelude.symbols) cold.prelude = _gather_prelude(cold.c);
  if (!(path in cold.prelude.visited)) {
    Compiler provider = _cold_provider(cold.c, path, cold.prelude);
    defer cold.c.close_child(provider);
    return _record_declared(provider);
  }
  if (!cold.prelude_session)
    cold.prelude_session = _cold_provider(cold.c, path, cold.prelude);
  cold.prelude_session.filename = path;
  return _record_declared(cold.prelude_session);
}

// Every file but `lib/x2c.x`, which declares no adoption, sees the prelude.
static Gathered _gather_prelude(Compiler c) {
  Gathered prelude = {.symbols = {}, .definitions = {}, .visited = {}};
  foreach (String source in Compiler.prelude_sources())
    _gather_declarations(c, _canonical_path(%"${x2c_get_root()}/$source"), prelude);
  return prelude;
}

/* A compiler of its own for the file at `path` that resolves the adoptions
   visible to it as the file's translation does: it sees the declarations
   of the prelude and of the file's include closure. */
static Compiler _cold_provider(
  Compiler c, String path, Gathered &prelude) {
  Compiler provider = Compiler.new_shared(c);
  provider.origins = [];
  provider.filename = path;
  provider.configure_package(c.package_source_dirs, path);
  Gathered view = {
    .symbols = prelude.symbols.copy(),
    .definitions = prelude.definitions.copy(),
    .visited = prelude.visited.copy()};
  _gather_declarations(provider, path, view);
  provider.fn_defs = view.definitions;
  provider.resolve_as_declared(view.symbols);
  return provider;
}

// Records the rows of the adoptions the current file declares in its entry.
static Map _record_declared(Compiler c) {
  Map rows = c.conformance_rows(c.declared_adoptions());
  c.record_conformance_rows(rows);
  return rows;
}

/* Adds the declarations and definitions of the file at `path` and of its
   includes, in source order, without installing their compile-time effects
   again. */
static void _gather_declarations(Compiler c, String path, Gathered &into) {
  if (path in into.visited) return;
  into.visited[path] = 1;
  List entry = _entry(c, path);
  if (!entry) return;
  foreach (String name in entry.caddr()) into.definitions[name] = 1;
  foreach (Var part in entry.car()) {
    if (part is <map>) into.symbols.merge(part);
    else if (part is <string>) _gather_declarations(c, part, into);
  }
}

/** Returns the collected source's public type families and the declarations
    of `names`, including their receiver rows. Includes contribute their
    selected declarations, without replaying compile-time effects.
    Unselected functions and variables do not enter the result.
*/
Map Compiler.callable_symbols(Compiler c, List names) {
  Gathered view = {.symbols = {}, .definitions = {}, .visited = {}};
  _gather_declarations(c, _canonical_path(c.filename), view);
  Map selected = {};
  foreach (Var (key, value) in view.symbols) {
    if (key is not <list> || value is not <list>) continue;
    if (_type_family(key)) {
      selected[key] = value;
      continue;
    }
    match (key) {
      case %(?name):
        if (name in names || %(typedef $name) in view.symbols)
          selected[key] = value;
      case %(self ?name): if (name in names) selected[key] = value;
      case %(?name "layout-attribute"):
        if (%(typedef $name) in view.symbols) selected[key] = value;
    }
  }
  return selected;
}

/* Sorted so that an entry does not depend on Map order. */
module List _sorted_names(Map definitions) {
  Array names = [];
  foreach (String name in definitions.keys()) names.push(name);
  names.sort();
  return names.list_free();
}

static Map _inline_type_dependencies(Compiler c, List ast) {
  Map rows = {};
  List function;
  $ast.walk(ast, function) {
    match (function)
      case %(function ?base (bind ?binding ?) ?body): {
        Type type = base;
        if (!type.is_inline() || type.is_static()) continue;
        Map types = {}, List node;
        $ast.walk(body, node) {
          match (node) {
            case %(expr ?type ?): if (type) types[type] = 1;
            case %((!set ?tag (!or declare decl typedef)) ?base
                     (bindings *bindings)):
              foreach (List binding in bindings) {
                Type type = %(declare $base (bindings $binding))
                  .type_from_ast();
                if (type) types[type] = 1;
              }
            case %(offsetof ?type ?): types[type] = 1;
            case %(op (!or . (!quote ->)) (expr ?receiver ?) ?): {
              Type aggregate = c.sym.aggregate_of(receiver);
              if (aggregate) types[aggregate] = 1;
            }
          }
        }
        Array ordered = [];
        foreach (Type type in types.keys()) ordered.push(type);
        String path = Compiler.portable_path(Path.absolute(c.filename));
        String name = Ast.binding_spelling(binding);
        rows[%("source-node" (interface-types $path ${-1} $name))] =
          %(interface-types $name ${ordered.sort().list_free()});
        continue;
      }
    match (function) {
      case %((!or seq at api-source) *): ;
      default: if (function.car() is <symbol>) continue;
    }
  }
  return rows;
}

/** Promotes the selected type families after the owning ordinary full
    parse. The header and Xi then use the same complete family selection. */
void Compiler.publish_inline_types(Compiler c, List ast) {
  Map additions = _inline_type_dependencies(c, ast);
  if (!additions.len()) return;
  String path = _canonical_path(c.filename);
  _publish_inline_dependencies(
    c, path, c.sym.unit_symbols(), c.sym.file_statics(), additions);
}

static void _publish_inline_dependencies(
  Compiler c, String path, Map all, Map statics, Map additions) {
  if (!additions.len()) return;
  List entry = _entry(c, path);
  if (!entry) return;
  Map needed = {}, selected = {};
  foreach (List value in additions) _needed_types(value, all, needed);
  int changed;
  do {
    changed = 0;
    foreach (Var (key, value) in all) {
      List family = _row_type_family(all, statics, key, value);
      if (!family || !(family in needed) || key in selected) continue;
      selected[key] = 1;
      additions[key] = value;
      if (value is <list>) _needed_types(value, all, needed);
      changed = 1;
    }
  } while (changed);
  Map published = {};
  foreach (Var part in entry.car())
    if (part is <map>)
      foreach (Var key in part.map().keys()) published[key] = part;
  Array dropped = $auto([]);
  foreach (List key in additions.keys()) {
    Var owner;
    if (published.try_get(key, owner) &&
        owner.map()[key] == additions[key]) dropped.push(key);
  }
  foreach (List key in dropped) additions.del(key);
  _cache_dependencies(entry[3], c.deps);
  if (!additions.len()) return;
  Map retained = _cache_copy(additions);
  _retain_rows(%($retained));
  Array replaced = $auto([]);
  foreach ((List key, Var value) in retained) {
    Var owner;
    if (!published.try_get(key, owner)) continue;
    owner.map()[key] = value;
    replaced.push(key);
  }
  foreach (List key in replaced) retained.del(key);
  if (!retained.len()) return;
  List parts = entry.car().list().append(%($retained));
  List updated = %($parts @{entry.cdr()});
  _require_retained(updated.try_own());
  _process_cache()[path] = updated;
}

/* The declaration map that the file's collected entry contributes, which is
   the map its interface publishes, or NULL when the file has none. */
static Map _contribution(String filename) {
  Var cached = _process_cache()[_canonical_path(filename)];
  if (cached is void) return NULL;
  Map contribution = NULL;
  foreach (Var part in cached.list().car())
    if (part is <map>) contribution = part;
  return contribution;
}

/** Records one generated public callable in the declaration map that the
    current file's collected entry contributes, which is the map its
    interface publishes. A file without a collected declaration map records
    nothing. The cache retains `signature`.
*/
void Compiler.record_generated_symbol(
  Compiler c, String name, Type signature) {
  Map contribution = _contribution(c.filename);
  if (contribution == NULL) return;
  List key = %($name), marker_key = %("generated-protocol" $name);
  List marker = %(generated);
  _require_retained(key.try_own());
  _require_retained(marker_key.try_own());
  _require_retained(marker.try_own());
  _require_retained(signature.try_own());
  contribution[key] = signature;
  contribution[marker_key] = marker;
}

/** Replaces the recorded conformance rows of the current file's collected
    entry with `rows`, which join the declaration map its interface
    publishes, as `record_generated_symbol` adds its rows. A row an earlier
    cold walk recorded may sit in an earlier map. The cache retains each key
    and value.
*/
void Compiler.record_conformance_rows(Compiler c, Map rows) {
  Var cached = _process_cache()[_canonical_path(c.filename)];
  if (cached is void) return;
  Map contribution = NULL;
  foreach (Var part in cached.list().car()) {
    if (part is not <map>) continue;
    contribution = part;
    Array stale = $auto([]);
    foreach (Var (key, value) in contribution)
      match (value) case %(conformance *): stale.push(key);
    foreach (Var key in stale) contribution.del(key);
  }
  if (contribution == NULL) return;
  foreach (List (key, value) in rows) {
    _retain(key);
    _retain(value);
    contribution[key] = value;
  }
}

/** Returns the `(adopt ...)` rows that the current file's collected entry
    declares, in no particular order. A file that imports a package
    declares none here: the walk that records them for a cold entry does
    not install a package's surface. */
List Compiler.declared_adoptions(Compiler c) {
  Var cached = _process_cache()[_canonical_path(c.filename)];
  if (cached is void) return NULL;
  Array adoptions = $auto([]);
  foreach (Var part in cached.list().car())
    if (part is <map>)
      foreach (Var value in part.map())
        match (value) {
          case %(adopt *): adoptions.push(value);
          case %(package-import *): return NULL;
        }
  return adoptions;
}
