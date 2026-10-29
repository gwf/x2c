/*  walk.x -- source collection walk

    Copyright (c) 2026 Gary William Flake.
*/

// the syntax prelude

/* `etc/compiler-prelude.x` declares the foundation types, the built-in
   macros' native prototypes, and the built-in macros and keyword aliases.
   Every unit collects it first, even one compiled without the runtime
   prelude. A compiler of its own walks it once per process as the
   compiler's own source; installing it during that walk installs nothing. */
static int syntax_walking = 0;

static const char syntax_marker[] = "_x2c.syntax.prelude";

// file walks

/* One cold walk of a file. Each segment of the text ends before an include,
   and `line` and `pos` locate the current segment's first token and `start`
   the preprocessor state there. `deferred` marks an entry collected
   without its declaration
   defaults. A module's walk reads its spliced text. */
module typedef struct FileWalk {
  Compiler c, String path, text, dir, ModuleSource module, Map globs, visited;
  Array parts, Map definitions, dependencies, statics, hashes;
  Cpp start;
  int unit, linkage, line, pos, deferred;
} FileWalk;

// collecting a unit

/** Collects the current translation unit's declarations into `globs`.
    The compiler must have its filename, text, and include paths prepared.
    `globs` is the base symbol map and is mutated; a null value starts from an
    empty map. A prelude unit first replays the runtime contribution, or
    walks `lib/x2c.x` cold when it must not skip runtime headers. The source
    and raw-include closure then merge in source order, and the returned map
    is `globs`. Collection also updates dependencies, function definitions,
    and macro state. Keyword alias maps and seen-name state are file-local
    and restored when each file walk ends.
*/
Map Compiler.collect_symbols(Compiler c, Map globs) {
  if (globs == NULL) globs = {};
  c.kw_aliases = {};
  Map visited = {}, String canonical = _canonical_path(c.filename);
  c.deps = {};
  c.add_translation_dependency(canonical);
  _add_syntax_prelude(c, globs, visited);
  if (c.prelude) _add_prelude(c, globs, visited);
  /* The prelude needs this file's signatures to close include cycles.
     Its own definitions must not suppress fresh declaration defaults.
     Keep type rows: public inline bodies can promote imported families. */
  if (canonical in visited)
    foreach (String name in _entry(c, canonical).caddr()) {
      globs.del($(name));
      globs.del(%(self $name));
      c.fn_defs.del(name);
    }
  visited[canonical] = 1;
  _walk_file(
    c, canonical, c.text, c.unit_source, Path.dirname(c.filename), globs,
    visited);
  _bind_pending_inline_bodies(c, globs, canonical);
  _record_cold_conformances(c, globs, visited, canonical);
  return globs;
}

/** Reports whether the canonical `path` is a compiler prelude source. */
int Compiler.is_prelude_source(String path) =>
  Compiler.portable_path(path) in Compiler.prelude_sources();

/** Installs the syntax prelude's macros and keyword aliases into `c`'s
    macro state once. A later file walk with the same macros, whose keyword
    aliases start empty, merges the aliases again.
*/
void Compiler.install_syntax_prelude(Compiler c) {
  Var installed;
  if (c.macros.try_get(syntax_marker, installed)) {
    c.kw_aliases.merge(installed);
    return;
  }
  List entry = _syntax_entry(c, _syntax_path());
  if (!entry) return;
  List effects = _syntax_effects(entry);
  c.install_compile_time_effects(effects);
  Map aliases = {};
  foreach (List row in effects)
    match (row) case %(compile-time keyword ?alias ?):
      aliases[alias] = c.kw_aliases[alias];
  c.macros[syntax_marker] = aliases;
}

// includes

/** Selects a source file's own package, as its standalone translation does.
    A cold provider does not register an import in its including unit.
*/
void Compiler.configure_package(Compiler c, List roots, String filename) {
  /* The lookup normalizes filename; only a match needs source membership. */
  String package = Compiler.package_directory(roots, filename);
  if (!package ||
      !Compiler.is_package_source(package, Path.absolute(filename))) return;
  String name = Path.basename(package);
  c.package = name;
  if (!(name in c.package_roots)) c.package_roots = c.package_roots.copy();
  c.package_roots[name] = package;
}

// replay

/** Prepares included compile-time effects after full parsing resets macros.
    The ordered cache walk counts each file once and groups effects by the
    canonical path of the unit's direct include. The parser installs those
    effects when it reaches that include.
*/
Map Compiler.included_compile_time_effects(Compiler c, Map globs) {
  Map visited = {}, delivered = {};
  if (c.prelude) {
    Array effects = [];
    foreach (String source in Compiler.prelude_sources()) {
      String path = _canonical_path(%"$(x2c_get_root())/$source");
      _replay_included(c, globs, path, visited, effects, NULL, NULL, NULL);
    }
    with (c.builtin_defs = 1) {
      c.install_compile_time_effects(effects.list_free());
    }
  }
  String unit = _canonical_path(c.filename);
  visited[unit] = 1;
  List entry = _entry(c, unit);
  if (!entry) return delivered;
  foreach (Var part in entry.car()) {
    Array exports = [];
    if (part is <map>) _replay_package_imports(c, globs, part, exports);
    else if (part is <string>) {
      _replay_included(c, globs, part, visited, exports, NULL, NULL, NULL);
      if (exports.len()) delivered[part] = exports.list_free();
    }
  }
  return delivered;
}

/* Builtin components contribute compile-time definitions beside the runtime
   prelude, with the shared source forms they recognize. They do not add
   compiler headers to a user's generated C. Their includes still declare
   into every unit, so they include no module outside `lib/x2c.x` with a
   public inline function, such as `lib/type.x`: a unit calling one would
   declare it without a definition. */
/** Returns the compiler-owned prelude sources relative to its home. Their
    runtime implementations are already linked into the shipped binaries.
*/
List Compiler.prelude_sources(void) => %(
  "lib/x2c.x" "src/grammar.x"
  "src/components/bracket-access.x"
  "src/components/try-catch.x"
  "src/components/delegate-members.x"
  "src/components/collection-literals.x"
  "src/components/printf-format.x"
  "src/components/dynamic-operators.x"
  "src/components/raise.x"
  "src/components/pattern-match.x"
  "src/components/interpolation.x"
  "src/components/destructuring.x"
  "src/components/lambda-functions.x"
  "src/components/protocol-adapters.x"
  "src/components/string-switch.x");

/** Installs the definitions of each include among the directives before
    the cursor.
*/
void Compiler.install_included_effects(Compiler c) {
  Token first = c.token, tokens = c.tokenizer.tokens;
  for (Token token = first; token > tokens;) {
    token--;
    if (token.type != <preproc> && token.type != <space> &&
        token.type != <comment>) break;
    first = token;
  }
  for (Token token = first; token < c.token; token++) {
    int angle = 0;
    String target = token.type == <preproc>
                  ? Compiler.preproc_include_target(token.text, angle) : NULL;
    if (!target) continue;
    String path = c.sources.resolve_include(
      c.include_dirs, Path.dirname(c.filename), target, angle);
    if (!path) continue;
    String canonical = _canonical_path(path);
    Var exports = c.included_effects[canonical];
    if (exports is void) continue;
    c.included_effects.del(canonical);
    // A conflict among the definitions is reported at their include line.
    with (c.token = token) { c.install_compile_time_effects(exports); }
  }
}

/* Macro effects use the same source-ordered parts as declaration replay.
   A currently collected file contributes only its recorded prefix. */
static List _macro_rows(Compiler c, String path, Map active) {
  Map runtime = _inside(path, _canonical_lib()) ? {} : _runtime_macros(c);
  Cpp cpp = Cpp.new({});
  Map visited = {};
  _replay_included(c, NULL, path, visited, NULL, active, cpp, runtime);
  Var rows = visited[path];
  return rows is void ? NULL : rows.list();
}

/* Directives retain their physical definition site across module splicing. */
static List _cpp_event(FileWalk &w, Token token) {
  int line = token.line;
  String file = w.path;
  if (w.module) {
    with (w.c.filename = w.path, w.c.line_markers = w.module.markers) {
      file = w.c.token_source(token, line);
    }
  }
  return %(cpp $(token.text) $(Compiler.portable_path(
    _canonical_path(file))) $line);
}

static void _replay_cpp(Compiler c, Cpp cpp, List event) {
  (Symbol kind, String text, String file, int line) = event;
  struct Token token = {.type = <preproc>, .text = text, .line = line};
  with (c.line_markers = NULL) {
    c.cpp_directive(cpp, &token, Compiler.absolute_home_path(file), NULL);
  }
}

/** Returns the `(name value)` macro rows that the file an `#include` of
    `target` from the directory `dir` names exports, or NULL when x2c does
    not read that file or has not collected it.
*/
List Compiler.included_macros(
  Compiler c, String target, int angle, String dir, Map active) {
  String path = c.sources.resolve_include(c.include_dirs, dir, target, angle);
  return path ? _macro_rows(c, _canonical_path(path), active) : NULL;
}

/** Returns the macro table visible before the first line of the file
    `path`: the macros the runtime defines, for a file outside `lib/`, and
    then those of the `-D` and `-U` options, for a file outside the runtime
    and the compiler's prelude, whose collection the options do not change.
    A NULL `path` sees neither.
*/
Map Compiler.initial_macros(Compiler c, String path) {
  if (!path) return {};
  String canonical = _canonical_path(path);
  Map runtime = _inside(canonical, _canonical_lib()) ? {} : _runtime_macros(c);
  return _initial_macros(c, canonical, runtime);
}

static Map _runtime_macros(Compiler c) {
  String runtime = %"$(x2c_get_root())/lib/x2c.x";
  return Cpp.table(_macro_rows(c, _canonical_path(runtime), NULL));
}

/* One replay shares only its immutable runtime baseline. Each file still
   starts from its own command-line policy, without includer definitions. */
static Map _initial_macros(Compiler c, String path, Map runtime) {
  Map macros = _inside(path, _canonical_lib()) ? {} : runtime.copy();
  if (!_runtime_source(path))
    macros.merge(Cpp.table(c.command_macros));
  return macros;
}

/** The file the include of `target` from `includer_dir` names, searched as
    collection searches `dirs`, or NULL.
*/
String SourceView.resolve_include(
  SourceView s, List dirs, String includer_dir, String target, int angle) {
  int covered = 0;
  return _resolve_include(
    s, dirs, includer_dir, target, angle, covered, NULL);
}

// source collection walk

static void _add_prelude(Compiler c, Map globs, Map visited) {
  foreach (String source in Compiler.prelude_sources()) {
    String path = %"$(x2c_get_root())/$source";
    String canonical = _canonical_path(path);
    visited[canonical] = 1;
    c.add_translation_dependency(canonical);
    if (c.runtime_hdrs)
      _walk_file(
        c, canonical, _runtime_text(c, path), NULL, Path.dirname(path), globs,
        visited);
    else {
      List entry = _prelude_entry(c, path, canonical);
      // Its compile-time effects install as the compiler's own.
      with (c.builtin_defs = 1) {
        _replay_cached(c, entry, canonical, globs, visited, NULL);
      }
    }
  }
}

static void _add_syntax_prelude(Compiler c, Map globs, Map visited) {
  String canonical = _syntax_path();
  visited[canonical] = 1;
  c.add_translation_dependency(canonical);
  List entry = _syntax_entry(c, canonical);
  with (c.builtin_defs = 1) {
    _replay_cached(c, entry, canonical, globs, visited, NULL);
  }
}

static String _syntax_path(void) =>
  _canonical_path(%"$(x2c_get_root())/etc/compiler-prelude.x");

static List _syntax_entry(Compiler c, String canonical) {
  List entry = _entry(c, canonical);
  if (entry || syntax_walking) return entry;
  Compiler file = Compiler.new_shared(c);
  defer c.close_child(file);
  file.interface_provider = 1;
  file.builtin_defs = 1;
  file.filename = canonical;
  Map visited = {};
  visited[canonical] = 1;
  with (syntax_walking = 1) {
    _walk_apart(file, canonical, _runtime_text(file, canonical), {}, visited);
  }
  return _process_cache()[canonical];
}

/* A prelude source's entry: cached in this process, linked into the
   compiler, read from its interface beside a stage build, or walked cold
   once. */
static List _prelude_entry(Compiler c, String runtime, String canonical) {
  List entry = _entry(c, canonical);
  if (entry) return entry;
  Map scratch = {}, visited = {};
  visited[canonical] = 1;
  _walk_apart(c, canonical, _runtime_text(c, runtime), scratch, visited);
  return _process_cache()[canonical];
}

module String _runtime_text(Compiler c, String runtime) {
  String text = NULL;
  if (c.read_source(runtime, text)) return text;
  $fail.collect_runtime_read(c, c.token, runtime);
}

/* Record declaration segments and include edges under canonical path
   identity. The first cold visit fixes a file's contribution for later
   units, so its declarations must not depend on unit-local names visible
   before the include. */
static void _walk_file(
  Compiler c, String path, String text, ModuleSource module, String dir,
  Map globs, Map visited) {
  if (path in _process_cache()) (void) _entry(c, path);
  if (module) text = module.text;
  Tokenizer tokenizer = Tokenizer.new(text, <x2c>);
  tokenizer.layout = Path.is_layout_source(path);
  tokenizer.scan();
  /* Keyword aliases are file-local, and every segment parses in the syntax
     the whole file selected. */
  with (c.collection_native = 0,
        c.kw_aliases = {},
        c.layout = tokenizer.layout) {
    FileWalk w = {
      .c = c, .path = path, .text = text, .dir = dir, .module = module,
      .globs = globs, .visited = visited, .parts = [], .definitions = {},
      .dependencies = _cache_map(), .statics = {}, .hashes = _cache_map(),
      .unit = Path.is_x2c_source(path), .line = 1};
    if (path == _canonical_path(c.filename)) c.meta_hashes = w.hashes;
    // Editing a member changes the module's contribution.
    if (module) {
      _cache_dependencies(w.dependencies, module.members);
      c.merge_translation_dependencies(module.members);
    }
    if (w.unit) {
      String provider = Compiler.portable_path(path);
      Map metadata = _cache_map();
      // Advertisements share this table while later segments fill it.
      metadata[%("source-node" (meta-hashes $provider 0))] =
        %(meta-hashes $provider $(w.hashes));
      w.parts.push(metadata);
      globs.merge(metadata);
    }
    // A cycle sees only the exports collected before its include.
    visited[path] = w.parts;
    _split(w, tokenizer.tokens);
    visited[path] = 1;
    _add_defaults(w);
    _queue_public_bodies(w);
    _select_public(w);
    _publish(w);
  }
}

/* The directives apply to the walk's preprocessor state in source order,
   and each segment starts from a copy of the state where it begins. The
   ordered parts retain its own directive events beside its include paths. */
static void _split(FileWalk &w, Token first) {
  Cpp cpp = Cpp.new(w.c.initial_macros(w.path));
  w.start = cpp.copy();
  for (Token token = first; token.type != <eof>; token++) {
    if (token.type != <preproc> || !_starts_line(first, token)) continue;
    String directive = Compiler.preproc_directive(token.text);
    if (Compiler.preproc_conditional_kind(token.text) ||
        directive.startswith("define") || directive.startswith("undef"))
      w.parts.push(_cpp_event(w, token));
    int split = !cpp.hidden() && _directive(w, token);
    w.c.cpp_directive(cpp, token, w.path, w.visited);
    if (split) w.start = cpp.copy();
  }
  _flush(w, w.text[w.pos:]);
}

/* An include ends the segment; reports whether `token` is one. The caller
   leaves out an include in an arm C never takes. */
static int _directive(FileWalk &w, Token token) {
  int angle = 0;
  String target = Compiler.preproc_include_target(token.text, angle);
  if (!target) return 0;
  _flush(w, w.text[w.pos:token.pos]);
  _include_file(w, target, angle);
  Token next = token + 1;
  w.line = next.line;
  w.pos = next.pos;
  return 1;
}

/* Splice one include: replay its entry, or walk it cold, once per unit.
   Its content hash joins this file's dependencies, so a replayed interface
   is rejected when any file it spliced has changed. */
static void _include_file(FileWalk &w, String target, int angle) {
  int covered = 0;
  String path = _resolve_include(
    w.c.sources, w.c.include_dirs, w.dir, target, angle, covered, w);
  if (!path || (covered && !Path.is_x2c_source(path))) return;
  String canonical = _canonical_path(path);
  w.c.add_translation_dependency(canonical);
  Var state;
  if (!w.visited.try_get(canonical, state)) {
    w.visited[canonical] = 1;
    List entry = _collection_entry(w.c, canonical);
    if (!entry) entry = _walk_cold(w.c, target, canonical, w.globs, w.visited);
    _replay_cached(
      w.c, entry, canonical, w.globs, w.visited, NULL);
  }
  else if (state is <array>)
    _replay_included(w.c, w.globs, canonical, {}, NULL, w.visited, NULL, NULL);
  _cache_dependency(
    w.dependencies, canonical, _walked_hash(w.c, target, canonical));
  w.parts.push(canonical);
}

/* Walk one included file cold and return its entry. The walk reads the
   includer's names through copies, so its private rows and includes stay
   there. It runs in a compiler of its own, with the macro, import, keyword,
   and binding state the file's own translation starts with. The includer
   replays the selected public definitions as any later unit would. */
module List _walk_cold(
  Compiler c, String target, String canonical, Map globs, Map visited) {
  String text = _include_text(c, target, canonical);
  Compiler file = Compiler.new_shared(c);
  defer c.close_child(file);
  file.interface_provider = 1;
  file.configure_package(c.package_source_dirs, canonical);
  file.signature_only = c.signature_only;
  file.filename = c.filename;
  /* A fresh file installs its own includes in its own macro state. Only
     active walks cross into that state, to preserve a cycle's prefix. */
  Map own_visited = {};
  foreach ((String path, Var state) in visited)
    if (state is <array>) own_visited[path] = state;
  _walk_apart(file, canonical, text, globs.copy(), own_visited);
  c.merge_translation_dependencies(file.deps);
  c.declaration_produced |= file.declaration_produced;
  return _process_cache()[canonical];
}

/* A cold included file has its own generated spellings. Binding identities
   remain unique across the unit and its pending inline-body parses. */
module void _walk_apart(
  Compiler c, String path, String text, Map globs, Map visited) {
  ModuleSource module = c.module_source(path, text, NULL);
  with (c.names.counters = {}) {
    _walk_file(c, path, text, module, Path.dirname(path), globs, visited);
  }
}

/* Replay declaration maps and includes in their recorded source order.
   visited counts each included file's declarations, dependencies, and
   function definitions once per translation unit. In-memory and interface
   entries have the same shape and take this same path. Source traversal
   keeps its processed prefix as a cold walk does. An effects array marks
   completed-provider replay for full parsing. */
module void _replay_cached(
  Compiler c, List entry, String path, Map globs, Map visited,
  Array effects) {
  Array prefix = effects != NULL ? NULL : [];
  if (prefix != NULL) visited[path] = prefix;
  foreach (String name in entry.caddr()) c.fn_defs[name] = 1;
  /* Parsing this file read these macro and embedded-text files. They are
     prerequisites of every unit that reaches it, not only of the one that
     parsed it. */
  c.merge_translation_dependencies(entry[3]);
  foreach (Var part in entry.car()) {
    if (part is <map>) {
      _merge_rows(c, globs, part);
      _replay_package_imports(c, globs, part, effects);
    }
    else if (part is <string>)
      _replay_include(c, part, globs, visited, effects);
    if (prefix != NULL) prefix.push(part);
  }
  if (prefix != NULL) visited[path] = 1;
}

/* An included file replays once per unit, from its entry or a cold walk. */
static void _replay_include(
  Compiler c, String path, Map globs, Map visited, Array effects) {
  c.add_translation_dependency(path);
  if (path in visited) return;
  visited[path] = 1;
  List entry = effects != NULL ? _entry(c, path) : _collection_entry(c, path);
  if (!entry) entry = _walk_cold(c, path, path, globs, visited);
  _replay_cached(c, entry, path, globs, visited, effects);
}

/* A directive's `#` follows only whitespace and comments on its line. */
static int _starts_line(Token first, Token token) {
  while (token-- > first) {
    if (token.type != <space> && token.type != <comment>) return 0;
    if ("\n" in token.text) return 1;
  }
  return 1;
}

// segments

/* Append one segment's nonempty published rows before the next part. */
static void _flush(FileWalk &w, String segment) {
  if (!segment || !*segment) return;
  Map overlay = _cache_map();
  _parse(w, segment, overlay);
  if (overlay.len()) w.parts.push(overlay);
}

/* A segment resolves names through cumulative globs but writes declarations
   only to overlay. shallow_parse_overlay expands applicable unit macros under
   semantic transactions, so their committed declarations and protocol rows
   are recorded at this segment's source position. Macro, keyword, and
   binding state then returns to the enclosing compiler for the next
   segment. */
static void _parse(FileWalk &w, String segment, Map overlay) {
  Compiler shadow = Compiler.new_shared(w.c);
  defer w.c.close_child(shadow);
  _prepare(w, shadow, segment);
  shadow.shallow_parse_overlay(w.globs, overlay);
  w.c.collection_native |= shadow.collection_native;
  w.linkage = shadow.open_linkage;
  shadow.return_unit_state(w.c);
  _merge_file(w, shadow, overlay);
}

/* The shadow parses the segment as part of this file, in the unit's state,
   with token lines and positions counted from the start of the file. */
static void _prepare(FileWalk &w, Compiler shadow, String segment) {
  if (!w.c.owns_package_source(w.path)) shadow.package = NULL;
  shadow.filename = w.path;
  shadow.load_source =
    w.c.load_source && w.path == Path.absolute(w.c.filename);
  // Every segment hashes its provider, including its private helpers.
  shadow.meta_hashes = w.hashes;
  shadow.layout = w.c.layout;
  shadow.source_private = 0;
  shadow.signature_only = w.c.signature_only;
  shadow.interface_provider = w.c.interface_provider;
  shadow.builtin_defs = w.c.builtin_defs;
  shadow.open_linkage = w.linkage;
  shadow.take_unit_state(w.c);
  shadow.cpp = w.start;
  shadow.scan_source(segment);
  shadow.text = w.text;
  if (w.module) shadow.line_markers = w.module.markers;
  if (w.c.source_facts)
    w.c.source_texts[Path.absolute(w.path)] =
      w.module ? w.module.own : w.text;
  _shift_tokens(shadow.tokenizer, w.line, w.pos);
  shadow.preprocess_tokens();
}

static void _shift_tokens(Tokenizer t, int line, int pos) {
  for (size_t i = 0; i < t.tokens.len(); i++) {
    Token token = &((struct Token *) t.tokens)[i];
    token.line += line - 1;
    token.pos += pos;
  }
}

/* The file takes every row the segment declared. Selection after the last
   segment can promote a static type needed by a later public declaration. */
static void _merge_file(FileWalk &w, Compiler shadow, Map overlay) {
  if (w.unit) {
    w.c.fn_defs.merge(shadow.fn_defs);
    w.definitions.merge(shadow.fn_defs);
  }
  /* A segment's import collects the package once for the whole unit. Its
     files are prerequisites of the unit and of this file's cache entry, so
     a later replay of the entry records them too. */
  _cache_dependencies(w.dependencies, shadow.deps);
  w.c.merge_translation_dependencies(shadow.deps);
  _merge_rows(w.c, w.globs, overlay);
  Map statics = shadow.sym.file_statics();
  w.statics.merge(statics);
  if (w.unit) _publish_unit_statics(statics, overlay, w.path);
}

/* Rows enter the unit's symbols and its source declarations together. */
module void _merge_rows(Compiler c, Map globs, Map rows) {
  globs.merge(rows);
  c.merge_source_declarations(globs, rows);
}

/* A file still being walked, as in an include cycle, has no entry yet. */
static String _walked_hash(Compiler c, String target, String canonical) {
  Var walked = _process_cache()[canonical];
  if (walked is void)
    return _content_hash(_include_text(c, target, canonical));
  return walked.list().cadr();
}

/* Read an include's text, reporting an unreadable target as a driver error. */
static String _include_text(Compiler c, String target, String path) {
  String text = NULL;
  if (c.read_source(path, text)) return text;
  $fail.collect_include_read(c, c.token, target, path);
}

/* `covered` is 1 when the file is in the runtime's `lib/` or
   `include/x2c`, which the prelude already covers. */
static String _resolve_include(
  SourceView sources, List extra_dirs, String includer_dir, String target,
  int angle, int &covered, FileWalk &?walk) {
  covered = 0;
  if (target.startswith("/")) {
    if (walk) _include_search_dependency(walk, target);
    return sources.exists(target) ? target : NULL;
  }
  Array dirs = auto _include_dirs(
    extra_dirs, angle ? NULL : includer_dir, !walk);
  for (int i = 0; i < dirs.len(); i++) {
    String dir = dirs[i], path = %"$dir/$target";
    covered = dir == _canonical_lib() || dir == _canonical_include();
    /* The final runtime header adds no symbols, generated or absent. */
    if (i + 1 < dirs.len() || !covered || Path.is_x2c_source(path))
      if (walk) _include_search_dependency(walk, path);
    if (!sources.exists(path)) continue;
    return path;
  }
  return NULL;
}

/* The runtime and the compiler's prelude are collected once for every
   unit, so the command line's macros do not reach them. */
module int _runtime_source(String canonical) =>
  _inside(canonical, _canonical_lib()) ||
  Compiler.is_prelude_source(canonical);

static int _inside(String path, String dir) =>
  path.startswith(dir) && path.len() > dir.len() && path[dir.len()] == '/';

/* Preserve absent candidates and alias identity, not directory timestamps.
   Canonical selected files already carry their ordinary content hashes. */
static void _include_search_dependency(FileWalk &w, String candidate) {
  if (!candidate.startswith("/")) candidate = %"cwd:$candidate";
  if (!candidate.startswith("cwd:") && w.c.sources.exists(candidate) &&
      candidate == _canonical_path(candidate)) return;
  String hash = _include_search_hash(w.c, candidate);
  _cache_dependency(w.dependencies, candidate, hash);
  w.c.deps.merge_translation_dependency(candidate, hash);
}

module String _include_search_hash(Compiler c, String path) {
  if (path.startswith("cwd:")) path = path[4:];
  return c.sources.exists(path) ?
    %"search:$(Compiler.portable_path(Path.absolute(path)))" : "search:absent";
}

/* The search order: the including file's directory for a quoted include,
   the working directory, the runtime's `lib/`, the compiler's `src/`,
   then the configured include directories. */
static Array _include_dirs(
  List extra_dirs, String includer_dir, int canonical) {
  Array dirs = [];
  if (includer_dir) dirs.push(_canonical_path(includer_dir));
  dirs.push(canonical ? _canonical_cwd() : ".");
  dirs.push(_canonical_lib());
  dirs.push(_canonical_src());
  foreach (Var dir in extra_dirs)
    if (dir is <string>) dirs.push(canonical ? _canonical_path(dir) : dir);
  return dirs;
}

// entries

/* Declaration producers select defaults for the file's declarations. */
static void _add_defaults(FileWalk &w) {
  if (w.c.signature_only || !_produces(w)) return;
  Map generated = w.c.select_declaration_defaults(
    w.path, w.globs, w.parts, w.definitions, w.statics);
  if (w.unit && generated) _publish_unit_statics(w.statics, generated, w.path);
  if (generated) w.parts.push(_cache_copy(generated));
}

/* Retain a cold provider's context until every included signature is
   collected. A cycle can refer to a declaration after its include. */
static void _queue_public_bodies(FileWalk &w) {
  if (!w.unit || !w.c.interface_provider) return;
  int private_types = 0;
  foreach (List key in w.statics.keys())
    if (_type_family(key)) private_types = 1;
  if (!private_types) return;
  int exposed = 0;
  foreach (Var part in w.parts) if (part is <map>)
    foreach (Var key in part.map().keys())
      if (key ~= %("function-inline" ?)) exposed = 1;
  if (!exposed) return;
  if (w.c.meta_build) {
    w.deferred = 1;
    return;
  }
  Map own = {};
  foreach (Var part in w.parts) if (part is <map>) own.merge(part);
  w.c.public_bodies = 1;
  w.c.pending_inline_bodies.push(
    $(
      w.c, w.path, w.text, w.globs, own, w.statics, w.hashes,
      @(w.module ? $(w.module.markers) : NULL)));
}

static int _produces(FileWalk &w) {
  foreach (Var part in w.parts) {
    if (part is not <map>) continue;
    foreach (Var value in part.map())
      if (value ~= %(declaration-source *)) return 1;
  }
  return 0;
}

/* Everything the entry holds is retained beyond the unit's pools. The first
   walk of a file fixes its contribution: a later walk of the same file, such
   as a unit whose text the prelude already covered, does not replace an
   entry that other units may already have replayed. */
static void _publish(FileWalk &w) {
  String hash = _content_hash(w.module ? w.module.own : w.text);
  if (w.unit) {
    Map metadata = _cache_map();
    String provider = Compiler.portable_path(w.path);
    if (w.c.collection_native) {
      metadata[%("collection-native")] = 1;
      w.c.collection_native_files[w.path] = 1;
    }
    // Keep the walk's proof before inline typing enriches entry dependencies.
    metadata[%("source-node" (provider-source $provider 0))] =
      %(source $hash $(_stored_dependencies(w.dependencies)));
    w.parts.push(metadata);
  }
  List parts = w.parts.list_free();
  _retain(w.path);
  _retain_rows(parts);
  foreach (String (name, hash) in w.hashes) {
    _retain(name);
    _retain(hash);
  }
  List definitions = _sorted_names(w.definitions);
  List roots = _interface_include_dirs(w.c, w.path);
  List entry = $(parts, hash, definitions, w.dependencies, roots);
  _require_retained(entry.try_own());
  Var prior = _process_cache()[w.path];
  if (prior is <list> && List.equal(prior.list()[4], roots)) return;
  _process_cache()[w.path] = entry;
  if (w.unit && _declares_adoption(parts)) {
    if (!cold_providers) cold_providers = _cache_map();
    cold_providers[w.path] = 1;
  }
  if (w.deferred || w.c.meta_build) {
    if (!provisional_entries) provisional_entries = _cache_map();
    provisional_entries[w.path] = 1;
  }
}

/* A root query visits each file once. Backedges and repeated includes
   consume that query's current prefix or completed rows, never a closure
   retained from an earlier query's include context. */
static void _replay_included(
  Compiler c, Map globs, String path, Map visited, Array exports,
  Map active, Cpp sink, Map runtime) {
  Var found;
  if (visited.try_get(path, found)) {
    if (sink) {
      if (found is <array>) {
        Array state = found;
        Cpp cpp = (Cpp) state[0].pointer();
        sink.merge(cpp.changes(state[1]));
      }
      else sink.merge(found);
    }
    return;
  }
  if (!sink) visited[path] = 1;
  Var prefix = active ? active[path] : void;
  List entry = prefix is <array> ? NULL : _entry(c, path);
  if (!entry && prefix is not <array>) return;
  List parts = prefix is <array> ? prefix.array().list() : entry.car();
  Map initial = sink ? _initial_macros(c, path, runtime) : NULL;
  Cpp cpp = sink ? Cpp.new(initial.copy()) : NULL;
  // Backedges read the live state; completed visits keep their final rows.
  if (cpp) visited[path] = [(void *) cpp, initial];
  foreach (Var part in parts) {
    if (part is <map> && !cpp)
      _replay_package_imports(c, globs, part, exports);
    else if (part is <string> && (!cpp || !cpp.hidden()))
      _replay_included(c, globs, part, visited, exports, active, cpp, runtime);
    else if (cpp && part is <list>) _replay_cpp(c, cpp, part);
  }
  if (cpp) {
    visited[path] = cpp.changes(initial);
    sink.merge(visited[path]);
  }
}

/* The compile-time rows of the syntax prelude's entry in source order. */
static List _syntax_effects(List entry) {
  Array rows = [];
  foreach (Var part in entry.car()) if (part is <map>)
    foreach (Var (key, value) in part.map())
      match (key) case %("source-node" (compile-time ? ?position)):
        rows.push($(position, value));
  rows.sort();
  Array effects = [];
  foreach (List row in rows) effects.push(row.cadr());
  return effects.list_free();
}
