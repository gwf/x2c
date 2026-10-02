/*  collect.x -- source-ordered shallow symbol collection and replay

    Raw collection scans includes without running cpp. Each cold walk
    records declaration maps and included paths at their source positions;
    cache and interface replay consume that same order so declaration
    precedence does not depend on whether a file was already collected. A
    translated unit writes its own contribution beside its generated C as a
    `.xi` interface, and the runtime prelude is `lib/x2c.xi`.
*/

#pragma once
#include "compiler.x"

#pragma private
$(import "../src/error-reports.xmacro")
$(import "../src/ast-rewrite.xmacro")
#include "buffer.x"
#include "datum.x"
#include "utils.x"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// the process cache

/* Process cache: canonical path ->
   `(ordered-parts hash definitions dependencies)`. A part is a declaration
   Map, an included source path, or a visibility marker. Dependencies map
   macro, Lisp, and embedded-text paths to a content hash or 1. Entries
   outlive per-unit scopes, so every retained key and value belongs to
   process_cache_scope. */
static Map process_cache = NULL, static Scope process_cache_scope = NULL;

/* Paths whose entries were collected without their declaration defaults
   while the shared compile-time session was being filled. */
static List preload_deferred = NULL;

static Map _process_cache(void) {
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
  preload_deferred = NULL;
}

static Map _cache_map(void) {
  $scope(&process_cache_scope) return {};
}

static Map _cache_copy(Map map) {
  $scope(&process_cache_scope) return map.copy();
}

/* A file's entry: collected in this process, or read from its interface. */
static List Compiler._entry(Compiler c, String canonical) {
  Var cached = _process_cache()[canonical];
  return cached is void ? c._interface_read(canonical) : cached;
}

static String _content_hash(String text) => "%08x".printf(text.hash());

static void _cache_dependency(Map dependencies, String path, Var hash) {
  _retain(path);
  _retain(hash);
  dependencies.merge_translation_dependency(path, hash);
}

static void _cache_dependencies(Map dependencies, Map additions) {
  foreach (Var (path, hash), additions)
    _cache_dependency(dependencies, path, hash);
}

/* A value the cache keeps must be owned beyond every unit's pools. */
static void _retain(Var value) {
  if (value is <list>) _require_retained(value.list().try_own());
  if (value is <string>) _require_retained(value.string().try_own());
}

static void _require_retained(int owned) {
  if (owned) return;
  fprintf(stderr, "x2c: could not retain process cache entry\n");
  abort();
}

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
  c.kw_aliases = NULL;
  c.kw_seen = NULL;
  Map visited = {}, String canonical = _canonical_path(c.filename);
  c.deps = {};
  c.add_translation_dependency(canonical);
  if (c.prelude) c._add_prelude(globs, visited);
  int covered = canonical in visited;
  visited[canonical] = 1;
  c._walk_file(canonical, c.text, Path.dirname(c.filename), globs, visited);
  /* The prelude's replay already declared this unit's defaults, so its own
     walk selects none of them. The first walk's declarations stay in force,
     as they are for every other unit that reaches this file. */
  if (covered)
    foreach (Var part, c._entry(canonical).car())
      if (part is <map>) c._merge_rows(globs, part);
  return globs;
}

static void Compiler._add_prelude(Compiler c, Map globs, Map visited) {
  String runtime = %"${x2c_get_root()}/lib/x2c.x";
  String canonical = _canonical_path(runtime);
  visited[canonical] = 1;
  c.add_translation_dependency(canonical);
  if (c.runtime_hdrs)
    c._walk_file(
      canonical, c._runtime_text(runtime), Path.dirname(runtime), globs,
      visited);
  else
    c._replay_cached(c._prelude_entry(runtime, canonical), globs, visited);
}

/* The prelude contribution is `lib/x2c.x`'s entry: cached in this process,
   read from `lib/x2c.xi` beside a stage build, or walked cold once. */
static List Compiler._prelude_entry(
  Compiler c, String runtime, String canonical) {
  List entry = c._entry(canonical);
  if (entry) return entry;
  Map scratch = {}, visited = {};
  visited[canonical] = 1;
  c._walk_apart(canonical, c._runtime_text(runtime), scratch, visited);
  return _process_cache()[canonical];
}

static String Compiler._runtime_text(Compiler c, String runtime) {
  String text = NULL;
  if (c.read_source(runtime, text)) return text;
  $report(c, "driver.runtime.read", runtime);
}

/* Rows enter the unit's symbols and its source declarations together. */
static void Compiler._merge_rows(Compiler c, Map globs, Map rows) {
  globs.merge(rows);
  c.merge_source_declarations(globs, rows);
}

// file walks

/* One cold walk of a file. Each segment of the text ends before an include
   or a visibility pragma, and `line` and `pos` locate the current segment's
   first token. `deferred` marks an entry collected without its declaration
   defaults. */
typedef struct FileWalk {
  Compiler c, String path, text, dir, Map globs, visited;
  Array parts, Map definitions, dependencies;
  int unit, private, linkage, line, pos, deferred;
} FileWalk;

/* Record a cold walk under canonical path identity. Published segment rows,
   included canonical paths, and visibility pragmas enter parts in source
   order, while source-private state carries only between segments of this
   file; every included file starts its own visibility state. An including
   unit replays private includes too, since it may call their functions, but
   a package publishes only the includes above its private boundary. The
   first cold visit fixes a header's contribution for later units, so its
   public declarations must not depend on unit-local names visible before
   the include. */
static void Compiler._walk_file(
  Compiler c, String path, String text, String dir, Map globs,
  Map visited) {
  Tokenizer tokenizer = Tokenizer.new(text, <x2c>);
  tokenizer.layout = is_layout_file(path);
  tokenizer.scan();
  /* Keyword aliases are file-local, and every segment parses in the syntax
     the whole file selected. */
  $let(c.declaration_effects, NULL) $let(c.kw_aliases, {})
  $let(c.kw_seen, {}) $let(c.layout, tokenizer.layout) {
    FileWalk w = {
      .c = c, .path = path, .text = text, .dir = dir, .globs = globs,
      .visited = visited, .parts = [], .definitions = {},
      .dependencies = _cache_map(), .unit = is_source_file(path), .line = 1};
    w.split(tokenizer.tokens);
    w.add_defaults();
    w.publish();
  }
}

static void FileWalk.split(FileWalk &w, Token first) {
  Array arms = $auto([]);
  for (Token token = first; token.type != <eof>; token++) {
    if (token.type != <preproc> || !_starts_line(first, token)) continue;
    if (!_track_arms(arms, token.text)) w.directive(token, _hidden(arms));
  }
  w.flush(w.text[w.pos:]);
}

/* An include or a visibility pragma ends the current segment. An include
   in an arm that C never takes is not read. */
static void FileWalk.directive(FileWalk &w, Token token, int hidden) {
  int angle = 0, visibility = preproc_visibility(token.text);
  String target = hidden ? NULL : preproc_include_target(token.text, angle);
  if (!target && visibility < 0) return;
  w.flush(w.text[w.pos:token.pos]);
  if (target) w.include(target, angle);
  else {
    w.private = visibility;
    w.parts.push(visibility ? <private> : <public>);
  }
  Token next = token + 1;
  w.line = next.line;
  w.pos = next.pos;
}

/* A directive's `#` follows only whitespace and comments on its line. */
static int _starts_line(Token first, Token token) {
  while (token-- > first) {
    if (token.type != <space> && token.type != <comment>) return 0;
    if (token.text.contains("\n")) return 1;
  }
  return 1;
}

/* Tracks the open conditional groups of a walk, one hidden-arm state each,
   and reports whether `text` is a conditional directive. */
static int _track_arms(Array arms, String text) {
  Symbol kind = preproc_conditional_kind(text);
  if (!kind) return 0;
  if (kind == <open>) arms.push(preproc_open_state(text));
  else if (kind == <branch> && arms.len())
    arms[-1] = preproc_branch_state(arms[-1]);
  else if (kind == <close> && arms.len()) arms.take_last();
  return 1;
}

static int _hidden(Array arms) {
  foreach (int state, arms) if (state == 2) return 1;
  return 0;
}

// segments

/* Append one segment's nonempty published rows before the next part. */
static void FileWalk.flush(FileWalk &w, String segment) {
  if (!segment || !*segment) return;
  Map overlay = _cache_map();
  w.parse(segment, overlay);
  if (overlay.len()) w.parts.push(overlay);
}

/* A segment resolves names through cumulative globs but writes declarations
   only to overlay. shallow_parse_overlay expands applicable unit macros under
   semantic transactions, so their committed declarations and protocol rows
   are recorded at this segment's source position. Macro, Lisp, and keyword
   state then returns to the enclosing compiler for the next segment. */
static void FileWalk.parse(FileWalk &w, String segment, Map overlay) {
  Compiler shadow = Compiler.new_shared(w.c);
  defer w.c.close_child(shadow);
  w.prepare(shadow, segment);
  shadow.shallow_parse_overlay(w.globs, overlay);
  w.linkage = shadow.open_linkage;
  shadow.return_unit_state(w.c);
  w.merge(shadow, overlay);
}

/* The shadow parses the segment as part of this file, in the unit's state,
   with token lines and positions counted from the start of the file. */
static void FileWalk.prepare(FileWalk &w, Compiler shadow, String segment) {
  if (!w.unit || !w.c._package_owns(w.path)) shadow.package = NULL;
  shadow.filename = w.path;
  // Included bodies belong to their own units; only this unit hashes ahead.
  if (w.path == _canonical_path(w.c.filename))
    shadow.meta_hashes = w.c.meta_hashes;
  shadow.layout = w.c.layout;
  shadow.source_private = w.private;
  shadow.open_linkage = w.linkage;
  shadow.take_unit_state(w.c);
  shadow.tokenize(segment);
  shadow.text = w.text;
  if (w.c.source_facts) w.c.source_texts[Path.absolute(w.path)] = w.text;
  _shift_tokens(shadow.tokenizer, w.line, w.pos);
}

static void _shift_tokens(Tokenizer t, int line, int pos) {
  for (size_t i = 0; i < t.tokens.len(); i++) {
    Token token = &((struct Token *) t.tokens)[i];
    token.line += line - 1;
    token.pos += pos;
  }
}

/* A package renames what it declares, not what it includes: only x2c source
   under its root takes its prefix. A C header, a runtime module, or foreign
   x2c source keeps its own spellings, as including that file directly gives
   them, so the collected entry is the same whichever unit walks it first. */
static int Compiler._package_owns(Compiler c, String path) {
  if (!c.package) return 0;
  Var root = c.package_roots[c.package];
  return root is not void &&
    path.startswith(%"${_canonical_path(root)}/");
}

/* The file takes every row the segment declared. What stays in the overlay
   afterwards is what the file publishes to an including unit. */
static void FileWalk.merge(FileWalk &w, Compiler shadow, Map overlay) {
  if (w.unit) {
    w.c.fn_defs.merge(shadow.fn_defs);
    w.definitions.merge(shadow.fn_defs);
  }
  /* A segment's import collects the package once for the whole unit. Its
     files are prerequisites of the unit and of this file's cache entry, so
     a later replay of the entry records them too. */
  _cache_dependencies(w.dependencies, shadow.deps);
  w.c.merge_translation_dependencies(shadow.deps);
  w.c._merge_rows(w.globs, overlay);
  Map statics = shadow.sym.file_statics();
  if (w.private) _keep_published_rows(statics, overlay);
  if (w.unit) _publish_unit_statics(statics, overlay, w.path);
}

/* Below `#pragma private`, an including unit sees only functions with
   external linkage and the protocol and declaration rows keyed by source
   position. Types, enumerators, objects, and static functions stay in the
   file, as they stay out of its generated header. */
static void _keep_published_rows(Map statics, Map overlay) {
  Array dropped = $auto([]);
  foreach (Var (key, value), overlay)
    if (!_crosses(statics, key, value)) dropped.push(key);
  foreach (Var key, dropped) overlay.del(key);
}

static int _crosses(Map statics, Var key, Var value) {
  match (%($key)) {
    case %(("source-node" *)): return 1;
    case %((?(String name))): return _external_function(statics, name, value);
    case %((self ?(String name))):
      return _external_function(statics, name, value);
  }
  return 0;
}

/* A private function row names a function that an including unit may call
   through the prototype x2c emits, unless it has internal linkage. */
static int _external_function(Map statics, String name, Var type) =>
  type is <list> && type.list().type().is_function() &&
  !(%(function $name) in statics);

/* A `static` function belongs to the file that defines it, above and below
   `#pragma private` alike, so its declaration row never crosses an include.
   The published marker names the defining file, which lets an including unit
   report a reference to the name instead of emitting a prototype that no
   object defines. The file is spelled home-portably, as interfaces spell
   paths. Only `.x` units publish markers; a C header's static inline
   functions belong to every file that includes it. */
static void _publish_unit_statics(Map statics, Map overlay, String path) {
  List owner = %(${home_portable_path(path)});
  foreach (Var key, statics.keys())
    match (%($key)) case %((function ?(String name))): {
      overlay.del(%($name));
      overlay.del(%(self $name));
      overlay[%("unit-static" $name)] = owner;
    }
}

// includes

/* Splice one include: replay its entry, or walk it cold, once per unit.
   Its content hash joins this file's dependencies, so a replayed interface
   is rejected when any file it spliced has changed. */
static void FileWalk.include(FileWalk &w, String target, int angle) {
  int covered = 0;
  String path = _resolve_include(
    w.c.sources, w.c.include_dirs, w.dir, target, angle, covered);
  if (!path || (covered && !is_source_file(path))) return;
  String canonical = _canonical_path(path);
  List entry = w.c._entry(canonical);
  w.c.add_translation_dependency(canonical);
  if (!(canonical in w.visited)) {
    w.visited[canonical] = 1;
    if (!entry) entry = w.c._walk_cold(target, canonical, w.globs, w.visited);
    w.c._replay_cached(entry, w.globs, w.visited);
  }
  _cache_dependency(
    w.dependencies, canonical, w.c._walked_hash(target, canonical));
  w.parts.push(canonical);
}

/* A file still being walked, as in an include cycle, has no entry yet. */
static String Compiler._walked_hash(
  Compiler c, String target, String canonical) {
  Var walked = _process_cache()[canonical];
  if (walked is void) return _content_hash(c._include_text(target, canonical));
  return walked.list().cadr();
}

/* Read an include's text, reporting an unreadable target as a driver error. */
static String Compiler._include_text(Compiler c, String target, String path) {
  String text = NULL;
  if (c.read_source(path, text)) return text;
  $report(c, "driver.include.read", target, path);
}

/* Walk one included file cold and return its entry. The walk reads the
   includer's names through copies, so its private rows and includes stay
   there; the includer replays the entry as any later unit would. */
static List Compiler._walk_cold(
  Compiler c, String target, String canonical, Map globs, Map visited) {
  String text = c._include_text(target, canonical);
  c._walk_apart(canonical, text, globs.copy(), visited.copy());
  return _process_cache()[canonical];
}

/* Walk a file other than the unit cold, then restore the unit's binding
   counter. The unit keeps only the file's entry and replays it as it would
   the file's interface, so it numbers its own bindings the same either way. */
static void Compiler._walk_apart(
  Compiler c, String path, String text, Map globs, Map visited) {
  int next_binding = c.names.next_binding;
  c._walk_file(path, text, Path.dirname(path), globs, visited);
  c.names.next_binding = next_binding;
}

/* `covered` is 1 when the file is in the runtime's `lib/` or
   `include/x2c`, which the prelude already covers. */
static String _resolve_include(
  SourceView sources, List extra_dirs, String includer_dir, String target,
  int angle, int &covered) {
  covered = 0;
  if (target.startswith("/")) return sources.exists(target) ? target : NULL;
  Array dirs = $auto(_include_dirs(extra_dirs, angle ? NULL : includer_dir));
  foreach (String dir, dirs) {
    String path = %"$dir/$target";
    if (!sources.exists(path)) continue;
    covered = dir == _canonical_lib() || dir == _canonical_include();
    return path;
  }
  return NULL;
}

/* The search order: the including file's directory for a quoted include,
   the working directory, the compiler's `src/` and `lib/`, then the
   configured include directories. */
static Array _include_dirs(List extra_dirs, String includer_dir) {
  Array dirs = [];
  if (includer_dir) dirs.push(_canonical_path(includer_dir));
  dirs.push(_canonical_cwd());
  dirs.push(_canonical_src());
  dirs.push(_canonical_lib());
  foreach (Var dir, extra_dirs)
    if (dir is <string>) dirs.push(_canonical_path(dir));
  return dirs;
}

/** The file the include of `target` from `includer_dir` names, searched as
    collection searches `dirs`, or NULL. */
String collect_resolve_include(
  SourceView sources, List dirs, String includer_dir, String target,
  int angle) {
  int covered = 0;
  return _resolve_include(sources, dirs, includer_dir, target, angle, covered);
}

/** The typedef names published by the files that the current unit's
    include of `target` reaches: the included file and, transitively, the
    includes above each file's `#pragma private`. A file already in `seen`
    is skipped with the files it reaches, and each file reached is added to
    `seen`. NULL when the include does not resolve to x2c source; a runtime
    module adds nothing the prelude has not declared. */
List Compiler.include_typedef_names(
  Compiler c, String target, int angle, Map seen) {
  String path = collect_resolve_include(
    c.sources, c.include_dirs, Path.dirname(c.filename), target, angle);
  if (!path || !is_source_file(path)) return NULL;
  Array names = [];
  c._add_typedef_names(names, _canonical_path(path), seen);
  return names.list_free();
}

static void Compiler._add_typedef_names(
  Compiler c, Array names, String path, Map seen) {
  if (path in seen || _in_runtime(path)) return;
  seen[path] = 1;
  List entry = c._entry(path);
  int private = 0;
  if (entry)
    foreach (Var part, entry.car())
      match (%($part)) {
        case %(?(Map rows)):
          foreach (Var key, rows.keys())
            match (%($key)) case %((typedef ?(String name))):
              names.push(name);
        case %(private): private = 1;
        case %(public): private = 0;
        case %(?(String include)):
          if (!private) c._add_typedef_names(names, include, seen);
      }
}

/* Unresolvable paths retain the caller's spelling. This is
   `Compiler.canonical_path` without a source view: an unsaved file keeps
   the spelling the include search built, which keys its process-cache
   entry, and `collect_resolve_include` searches with no Compiler. */
static String _canonical_path(String path) {
  char buffer[PATH_MAX];
  return realpath(path, buffer) ? buffer : path;
}

/* Canonical process-wide include roots. */
static String _cached_canonical(char *cache, String dir) {
  if (!*cache && !realpath(dir, cache))
    snprintf(cache, PATH_MAX, "%s", (char *) dir);
  return cache;
}

static String _canonical_lib(void) {
  static char cache[PATH_MAX];
  if (*cache) return cache;
  return _cached_canonical(cache, %"${x2c_get_root()}/lib");
}

static String _canonical_include(void) {
  static char cache[PATH_MAX];
  if (*cache) return cache;
  return _cached_canonical(cache, %"${x2c_get_root()}/include/x2c");
}

static String _canonical_src(void) {
  static char cache[PATH_MAX];
  if (*cache) return cache;
  return _cached_canonical(cache, %"${x2c_get_root()}/src");
}

static String _canonical_cwd(void) {
  static char cache[PATH_MAX];
  return _cached_canonical(cache, ".");
}

// entries

/* Declaration producers run the syntax builders, which the shared session
   lacks while `lib/meta.x` is preloading. That walk's entry for a producing
   file is dropped afterwards, so a later unit walks the file again with the
   builders. */
static void FileWalk.add_defaults(FileWalk &w) {
  if (!w.produces()) return;
  w.deferred = macro_library_filling();
  if (w.deferred) return;
  Map generated = w.c.select_declaration_defaults(
    w.path, w.globs, w.parts, w.definitions);
  if (generated) w.parts.push(_cache_copy(generated));
}

static int FileWalk.produces(FileWalk &w) {
  foreach (Var part, w.parts) {
    if (part is not <map>) continue;
    foreach (Var value, part.map())
      match (value) case %(declaration-source *): return 1;
  }
  return 0;
}

/* Everything the entry holds is retained beyond the unit's pools. The first
   walk of a file fixes its contribution: a later walk of the same file, such
   as a unit whose text the prelude already covered, does not replace an
   entry that other units may already have replayed. */
static void FileWalk.publish(FileWalk &w) {
  List parts = w.parts.list_free();
  _retain(w.path);
  _retain_rows(parts);
  String hash = _content_hash(w.text);
  List definitions = _sorted_names(w.definitions);
  List entry = %($parts $hash $definitions ${w.dependencies});
  _require_retained(entry.try_own());
  if (w.path in _process_cache()) return;
  _process_cache()[w.path] = entry;
  if (w.deferred) $scope(&process_cache_scope)
    preload_deferred = cons(w.path, preload_deferred);
}

/* Sorted so that an entry does not depend on Map order. */
static List _sorted_names(Map definitions) {
  Array names = [];
  foreach (Var name, definitions.keys()) names.push(name);
  names.sort();
  return names.list_free();
}

static void _retain_rows(List parts) {
  foreach (Var part, parts) {
    if (part is not <map>) continue;
    foreach (Var (key, value), part.map()) {
      _retain(key);
      _retain(value);
    }
  }
}

/** Records one generated public callable in the declaration map that the
    current file's collected entry contributes, which is the map its
    interface publishes. A file without a collected declaration map records
    nothing. The cache retains `signature`.
*/
void Compiler.record_generated_symbol(
  Compiler c, String name, Type signature) {
  Var cached = _process_cache()[_canonical_path(c.filename)];
  if (cached is void) return;
  Map contribution = NULL;
  foreach (Var part, cached.list().car())
    if (part is <map>) contribution = part;
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

// replay

/* Replay declaration maps and includes in their recorded source order.
   visited counts each included file's declarations, dependencies, and
   function definitions once per translation unit. In-memory and interface
   entries have the same shape and take this same path. */
static void Compiler._replay_cached(
  Compiler c, List entry, Map globs, Map visited) {
  foreach (Var name, entry.caddr()) c.fn_defs[name] = 1;
  /* Parsing this file read these macro and Lisp files. They are
     prerequisites of every unit that reaches it, not only of the one that
     parsed it. */
  c.merge_translation_dependencies(entry[3]);
  foreach (Var part, entry.car()) {
    if (part is <map>) {
      c._merge_rows(globs, part);
      c.replay_package_imports(globs, part, 0);
    }
    else if (part is <string>) c._replay_include(part, globs, visited);
  }
}

/* An included file replays once per unit, from its entry or a cold walk. */
static void Compiler._replay_include(
  Compiler c, String path, Map globs, Map visited) {
  c.add_translation_dependency(path);
  if (path in visited) return;
  visited[path] = 1;
  List entry = c._entry(path);
  if (!entry) entry = c._walk_cold(path, path, globs, visited);
  c._replay_cached(entry, globs, visited);
}

// package imports

/* One package's public surface while it is gathered: the package's name
   and root, the rows merged so far, the files already visited, and the
   token that locates errors. */
typedef struct Surface {
  Compiler c, String name, root, Map merged, visited, Token token;
} Surface;

/** Collects a package once and installs its public surface in the current
    unit.
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
  String entry = c._find_package(name, root, token);
  /* The root is registered before the walk, as a package unit's own is
     before its parse, so the walk can tell the package's files apart. */
  c.package_roots[name] = root;
  c.select_package_module(name, root, token);
  Compiler package = Compiler.new_shared(c);
  defer c.close_child(package);
  package.package = name;
  package.filename = entry;
  c._walk_package(package, entry, token);
  c.fn_defs.merge(package.fn_defs);
  Surface s = {
    .c = c, .name = name, .root = root, .merged = {}, .visited = {},
    .token = token};
  s.visited[entry] = 1;
  c.add_translation_dependency(entry);
  s.gather(entry, _process_cache()[entry]);
  s.install();
}

static String Compiler._find_package(
  Compiler c, String name, String &root, Token token) {
  String entry = package_entry(c.sources, c.package_dirs, name, root);
  if (entry) return entry;
  $report(c, "driver.package.unknown", token, name);
}

/* The package's files enter the cache from their entries, or from one cold
   walk in package mode. */
static void Compiler._walk_package(
  Compiler c, Compiler package, String entry, Token token) {
  Map globs = c.sym.base_symbols(), visited = {};
  visited[entry] = 1;
  List cached = c._entry(entry);
  if (cached) {
    package._replay_cached(cached, globs, visited);
    return;
  }
  String text = NULL;
  if (!package.read_source(entry, text))
    $report(c, "driver.package.read", token, package, entry);
  package._walk_apart(entry, text, globs, visited);
}

/* Replay one cached entry for its declarations only, recording each package
   file as a dependency of the importing unit. An include below the file's
   private boundary is not part of the package surface. */
static void Surface.gather(Surface &s, String path, List entry) {
  s.c.merge_translation_dependencies(entry[3]);
  int private = 0;
  foreach (Var part, entry.car())
    match (%($part)) {
      case %(?(Map rows)): s.merge(path, rows);
      case %(private): private = 1;
      case %(public): private = 0;
      case %(?(String include)): s.include(include, private);
      default: __builtin_unreachable();
    }
}

static void Surface.include(Surface &s, String path, int private) {
  s.c.add_translation_dependency(path);
  if (private || path in s.visited) return;
  s.visited[path] = 1;
  s.gather(path, _process_cache()[path]);
}

/* The package's `name__` space is visible in the importing unit, and so is
   a C header or runtime module it publishes: a package renames what it
   declares, not what it includes, so those names cross as including that
   file gives them. Inside the package root an unprefixed x2c key is a
   static, which keeps C internal linkage and stays home; outside it the file
   escaped the declare-time rewrite and its bare names would merge into the
   consumer's one flat namespace. */
static void Surface.merge(Surface &s, String path, Map rows) {
  String prefix = %"${s.name}__";
  int keeps = _keeps_spellings(path);
  int foreign = !path.startswith(%"${s.root}/");
  foreach (Var (key, value), rows) {
    if (key is not <list> || key.is_nil()) continue;
    String spelling = _package_key_spelling(key);
    if (_package_protocol_row(key, value)) s.take(rows, key, value);
    else if (spelling && (keeps || spelling.startswith(prefix)))
      s.take(rows, key, value);
    else if (spelling && foreign) s.reject(path, spelling);
  }
}

static void Surface.take(Surface &s, Map rows, List key, Var value) {
  s.merged[key] = value;
  s.c.copy_source_declaration(s.merged, rows, key);
}

static void Surface.reject(Surface &s, String path, String spelling) {
  String name = s.name, unit = path.split("/").last();
  String fix = %"below #pragma private, or move it into '$name/src'";
  $report(s.c, "driver.package.prefix", s.token, name, spelling, unit, fix);
}

/* The merged rows enter the importing unit's symbols. */
static void Surface.install(Surface &s) {
  foreach (Var (key, value), s.merged) {
    s.c.sym.set(key, value);
    s.c.copy_source_declaration(s.c.sym.current_symbols(), s.merged, key);
  }
}

/* A C header or a runtime module crosses with its own spellings. */
static int _keeps_spellings(String path) =>
  !is_source_file(path) || _in_runtime(path);

/* A canonical path in the runtime's `lib/` or `include/x2c`. */
static int _in_runtime(String path) =>
  path.startswith(%"${_canonical_lib()}/") ||
  path.startswith(%"${_canonical_include()}/");

/* A declaration key is a plain name, or a typedef or aggregate name that a
   member row may extend; the tag covers the whole family, so a member of a
   prefixed aggregate crosses with it. Source-node and helper rows carry no C
   spelling of their own. */
static String _package_key_spelling(List key) {
  Var (head, spelling_value) = key;
  if (head is <string>) {
    String spelling = head;
    if (key.cdr() || spelling == "source-node") return NULL;
    return spelling == "source-typedef" ? NULL : spelling;
  }
  if (head == <self>)
    return key.cdr() && !key.cddr() && spelling_value is <string>
         ? spelling_value : NULL;
  if (head != <typedef> && head != <struct> &&
      head != <union> && head != <enum>) return NULL;
  return key.cdr() && spelling_value is <string>
       ? spelling_value : NULL;
}

/* Protocol declarations and adoptions are keyed by source location instead
   of by a spelling, and a package's rows already name its own prefixed
   types, so they cross with the rest of its surface. */
static int _package_protocol_row(List key, Var value) {
  if (key.car() != "source-node" || value is not <list>) return 0;
  List row = value;
  return row && row.car() in
    %(protocol adopt meta-protocol declaration-source native-meta
      package-macro package-import);
}

// import replay

/** Replays the import operations retained by this declaration contribution.
    The shadow borrows the unit's macro state and shared package registries.
*/
void Compiler.replay_package_imports(
  Compiler c, Map globs, Map rows, int included_only) {
  Array imports = NULL;
  defer if (imports) imports.free();
  foreach (Var (key, value), rows)
    match (key)
      case %("source-node" (package-import ?path ?position)):
        if (!included_only || !c._imported_here(path)) {
          if (!imports) imports = [];
          imports.push(%($path $position $value));
        }
  if (!imports.len()) return;
  imports.sort();
  c._import_all(globs, imports);
}

/* An import the unit itself wrote stays at its own source site. */
static int Compiler._imported_here(Compiler c, String path) =>
  _canonical_path(home_absolute_path(path)) == _canonical_path(c.filename);

static void Compiler._import_all(Compiler c, Map globs, Array imports) {
  Compiler shadow = Compiler.new_shared(c);
  defer c.close_child(shadow);
  shadow.take_unit_state(c);
  shadow.sym.reset(globs);
  foreach (List entry, imports)
    match (entry)
      case %(?(String path) ?
             (package-import ?(String name) ?(String alias) ?members)):
        shadow._import_package(path, name, alias, members);
  shadow.return_unit_state(c);
  c.merge_translation_dependencies(shadow.deps);
}

static void Compiler._import_package(
  Compiler c, String path, String name, String alias, List members) {
  c.filename = home_absolute_path(path);
  c.collect_package(name, NULL);
  c.register_package_alias(name, alias, NULL);
  foreach (List member, members)
    c.register_package_member(name, member.car(), member.cadr(), NULL, NULL);
  c.import_package_macros(name, NULL);
}

/** Repeats included imports after full parsing resets macros, in the
    cache's original include order. The unit's own imports stay at their
    source sites.
*/
void Compiler.replay_included_package_imports(
  Compiler c, Map globs, String path, Map visited) {
  String canonical = _canonical_path(path);
  if (canonical in visited) return;
  visited[canonical] = 1;
  List entry = c._entry(canonical);
  if (!entry) return; // An unresolved C include has no collection entry.
  foreach (Var part, entry.car()) {
    if (part is <map>) c.replay_package_imports(globs, part, 1);
    else if (part is <string>)
      c.replay_included_package_imports(globs, part, visited);
  }
}

// unit interfaces

/* A `.xi` interface is one unit's cache entry written beside its generated
   C. It records the identity of the compiler that wrote it, because a
   different compiler may collect different rows from the same source.
   Missing, stale, foreign, or malformed interfaces are cache misses; the
   caller walks the file cold and installs that result in the process cache.
   Paths inside an interface use `home_portable_path` spellings. */

static String interface_out_dir = NULL, interface_mirror = NULL;

/* Interfaces name the same sources many times, so a process hashes each
   source once. */
static Map source_hashes = NULL, static Lisp interface_reader = NULL;

/** Creates the process cache and names the directories searched for `.xi`
    interfaces. `out_dir` is the current translation output directory, or
    NULL. Home files mirror their home-relative path under the compiler's
    stage directory when it runs from `<home>/builds/`, otherwise under the
    home. A `cold` process reads no interface and still writes its own. Call
    it before opening any translation unit's Context.
*/
void interface_configure(String out_dir, int cold) {
  _process_cache();
  interface_out_dir = out_dir;
  String stage = stage_dir();
  interface_mirror = cold ? NULL : stage ? stage : x2c_get_root();
}

/* Find and validate the interface of one canonical source path. A source
   under inspection through a SourceView never reads interfaces. */
static List Compiler._interface_read(Compiler c, String canonical) {
  if (c.source_facts || !interface_mirror) return NULL;
  foreach (String path, _interface_candidates(canonical)) {
    List entry = c._interface_load(canonical, path);
    if (entry) return entry;
  }
  return NULL;
}

/* Candidate interface paths for one canonical source path: the output
   directory by stem, its sibling that mirrors a home file's directory, the
   home mirror, and a package's `builds/` beside or above the source. */
static List _interface_candidates(String canonical) {
  String stem = Path.stem(canonical), relative = home_portable_path(canonical);
  String dir = Path.dirname(canonical), Array paths = [];
  if (interface_out_dir) paths.push(%"$interface_out_dir/$stem.xi");
  if (relative != canonical) {
    String mirror = %"${Path.dirname(relative)}/$stem.xi";
    if (interface_out_dir) paths.push(%"$interface_out_dir/../$mirror");
    paths.push(%"$interface_mirror/$mirror");
  }
  paths.push(%"$dir/builds/$stem.xi");
  paths.push(%"$dir/../builds/$stem.xi");
  return paths.list_free();
}

/* Materialize one interface file only after its compiler identity, source
   path and hash, and the content hashes of the includes, macros, Lisp, and
   embedded text it depends on, validate. The entry uses process_cache_scope
   ownership and the same ordered parts representation as a cold walk. The
   interface's selected definition rows are not read back. */
static List Compiler._interface_load(
  Compiler c, String canonical, String path) {
  match (_interface_record(path))
    case %(interface 4 ?(String compiler) ?(String owner) ?(String hash)
           ?(List parts) ?(List definitions) ? ?(List dependencies)):
      if (c._interface_current(canonical, compiler, owner, hash))
        return c._interface_entry(
          canonical, hash, parts, definitions, dependencies);
  return NULL;
}

/* The file's one List form, or NULL when it is missing or unreadable. */
static List _interface_record(String path) {
  File input = fopen(path, "r");
  if (!input) return NULL;
  String source = NULL;
  try source = input.string_close();
  catch %(io-fail *): return NULL;
  unsigned cursor = 0;
  Var record = void;
  Symbol status = 0;
  try status = Lisp.read(_interface_lisp(), source, cursor, record);
  catch %((!or incomplete malformed) *): return NULL;
  if (status != <value> || record is not <list>) return NULL;
  return record;
}

static Lisp _interface_lisp(void) {
  if (interface_reader) return interface_reader;
  _process_cache();
  $scope(&process_cache_scope) {
    interface_reader = Lisp.kernel();
    source_hashes = {};
    Scope.shutdown_hook(_interface_shutdown);
  }
  return interface_reader;
}

static void _interface_shutdown(void) {
  Lisp.destroy(interface_reader);
  interface_reader = NULL;
  source_hashes = NULL;
}

/* The interface belongs to this compiler and this source, and the source
   still hashes as it did when the interface was written. */
static int Compiler._interface_current(
  Compiler c, String canonical, String compiler, String owner, String hash) {
  String identity = compiler_identity();
  return identity && compiler.equal(identity) &&
    home_absolute_path(owner).equal(canonical) &&
    c._hash_matches(canonical, hash);
}

static int Compiler._hash_matches(Compiler c, String path, Var expected) {
  if (expected is not <string>) return 0;
  String hash = c._source_hash(path);
  return hash && String.equal(hash, expected);
}

/* NULL when the source cannot be read. */
static String Compiler._source_hash(Compiler c, String path) {
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
static List Compiler._interface_entry(
  Compiler c, String canonical, String hash, List stored_parts,
  List definitions, List stored_dependencies) {
  Array parts = [];
  if (!_read_parts(parts, stored_parts)) return NULL;
  Map dependencies = c._read_dependencies(stored_dependencies);
  if (dependencies == NULL) return NULL;
  foreach (Var definition, definitions)
    if (definition is not <string>) return NULL;
  List entry = %(${parts.list_free()} $hash $definitions $dependencies);
  _retain(canonical);
  _require_retained(entry.try_own());
  _process_cache()[canonical] = entry;
  return entry;
}

/* A stored part is an include path, a visibility marker, or a list of
   rows. */
static int _read_parts(Array parts, List stored) {
  foreach (Var part, stored) {
    if (part is <string>)
      parts.push(_canonical_path(home_absolute_path(part)));
    else if (part == <private> || part == <public>) parts.push(part);
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
  foreach (Var row, stored) {
    if (row is not <list> || row.list().len() != 2) return NULL;
    List pair = row;
    _require_retained(pair.try_own());
    Var (key, value) = pair;
    rows[key] = value;
  }
  return rows;
}

/* Each dependency still hashes as it did when the interface was written; a
   hash of 1 marks a file that is not hashed. */
static Map Compiler._read_dependencies(Compiler c, List stored) {
  Map dependencies = _cache_map();
  foreach (Var dependency, stored) {
    if (dependency is not <list>) return NULL;
    match (dependency.list())
      case %(?(String name) ?hash): {
        String path = _canonical_path(home_absolute_path(name));
        int unhashed = hash.is_integer() && hash.integer() == 1;
        if (!unhashed && !c._hash_matches(path, hash)) return NULL;
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
String interface_prelude(void) {
  String identity = compiler_identity();
  if (!identity) return NULL;
  String runtime = _canonical_path(%"${x2c_get_root()}/lib/x2c.x");
  String header = %"(interface 4 \"$identity\" ";
  foreach (String path, _interface_candidates(runtime)) {
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
String interface_text(Compiler c, List selected) {
  if (!compiler_identity()) return NULL;
  String canonical = _canonical_path(c.filename);
  Var cached = _process_cache()[canonical];
  if (cached is void) return NULL;
  Buffer out = $auto(Buffer.new(0));
  if (_write_interface_entry(out, canonical, cached, selected)) return out;
  $report(c, "emit.interface.write");
}

static int _write_interface_entry(
  Buffer out, String canonical, List entry, List selected) {
  (List cached_parts, Var hash, List definitions, Map dependencies) = entry;
  Map identities = {}, Array parts = [];
  foreach (Var part, cached_parts) parts.push(_stored_part(part, identities));
  List record = %(
    interface 4 ${compiler_identity()} ${home_portable_path(canonical)}
    $hash ${parts.list_free()} $definitions
    ${_renumber_bindings(selected, identities)}
    ${_stored_dependencies(dependencies)}
  );
  /* An interface is plain data, which a loader never evaluates. */
  if (!datum_write(out, record, 0)) return 0;
  out.write_char('\n');
  return 1;
}

/* A stored part is a visibility marker, a home-portable include path, or
   the sorted rows of a declaration map with bindings renumbered. */
static Var _stored_part(Var part, Map identities) {
  if (part is <symbol>) return part;
  if (part is not <map>) return home_portable_path(part);
  Array rows = [];
  foreach (Var (key, value), part.map()) rows.push(%($key $value));
  rows.sort();
  return _renumber_bindings(rows.list_free(), identities);
}

static List _stored_dependencies(Map dependencies) {
  Array rows = [];
  foreach (Var (path, hash), dependencies)
    rows.push(%(${home_portable_path(path)} $hash));
  rows.sort();
  return rows.list_free();
}

/* A cold walk numbers bindings from wherever the shared counter stands, which
   depends on the files walked before it. An interface renumbers them in order
   of first appearance, keeping equal bindings equal. */
static List _renumber_bindings(List node, Map identities) {
  String spelling = NULL;
  if (binding_identity_try_parts(node, NULL, spelling)) {
    Var identity = identities.setdefault(node, identities.len() + 1);
    return binding_identity_new(identity, spelling);
  }
  Var child;
  $ast.rewrite_children(
    node, child, _renumber_bindings(child, identities));
}

// cache lifecycle

/** Drops the entries collected without declaration defaults while the shared
    compile-time session was filled. Call once that session is published. */
void collect_forget_preload_entries(void) {
  foreach (String path, preload_deferred) (void) _process_cache().del(path);
  preload_deferred = NULL;
}

/** Returns the canonical paths collected so far. */
List collect_cached_paths(void) => _process_cache().keys();

/** Drops the entries collected since `before` returned by
    `collect_cached_paths`. A cached entry replays declarations, not the
    compile-time effects of the file's imports, which the unit that walked
    it installed in its own session. */
void collect_forget_entries_since(List before) {
  Map kept = {};
  foreach (String path, before) kept[path] = 1;
  // A deletion moves later slots, so an open key iterator would skip some.
  List paths = _process_cache().keys();
  foreach (String path, paths)
    if (!(path in kept)) (void) _process_cache().del(path);
}
