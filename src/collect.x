/* collect.x -- source-ordered shallow symbol collection and replay

   Raw collection scans includes without running cpp. Each cold walk records
   declaration maps and included paths at their source positions; cache and
   interface replay consume that same order so declaration precedence does
   not depend on whether a file was already collected. A translated unit
   writes its own contribution beside its generated C as a `.xi` interface,
   and the runtime prelude is `lib/x2c.xi`.
*/

#pragma once
#include "compiler.x"

#pragma private
$(import "../src/ast-rewrite.xmacro")
#include "buffer.x"
#include "utils.x"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* A directive's `#` follows only whitespace and comments on its line. */
static int _starts_line(Token first, Token token) {
  while (token-- > first) {
    if (token.type != <space> && token.type != <comment>) return 0;
    if (token.text.contains("\n")) return 1;
  }
  return 1;
}

/* Unresolvable paths retain the caller's spelling. */
static String _canonical_path(String path) {
  char buffer[PATH_MAX];
  return realpath(path, buffer) ? %"$buffer" : path;
}

/* Canonical process-wide include roots. */
static String _cached_canonical(char *cache, String dir) {
  if (!*cache && !realpath(dir, cache))
    snprintf(cache, PATH_MAX, "%s", (char *) dir);
  return %"$cache";
}

static String _canonical_lib(void) {
  static char cache[PATH_MAX];
  if (*cache) return %"$cache";
  return _cached_canonical(cache, %"${x2c_get_root()}/lib");
}

static String _canonical_include(void) {
  static char cache[PATH_MAX];
  if (*cache) return %"$cache";
  return _cached_canonical(cache, %"${x2c_get_root()}/include/x2c");
}

static String _canonical_src(void) {
  static char cache[PATH_MAX];
  if (*cache) return %"$cache";
  return _cached_canonical(cache, %"${x2c_get_root()}/src");
}

static String _canonical_cwd(void) {
  static char cache[PATH_MAX];
  return _cached_canonical(cache, ".");
}

static String _resolve_include_dirs(
  SourceView sources, List extra_dirs, String includer_dir, String target,
  int angle, int *covered) {
  *covered = 0;
  if (target.startswith("/"))
    return sources.exists(target) ? target : NULL;
  String lib_dir = _canonical_lib(), include_dir = _canonical_include();
  Array dirs = [];
  if (!angle && includer_dir) dirs.push(_canonical_path(includer_dir));
  dirs.push(_canonical_cwd());
  dirs.push(_canonical_src());
  dirs.push(lib_dir);
  foreach (Var value, extra_dirs) {
    if (value is not <string>) continue;
    String dir = value;
    dirs.push(_canonical_path(dir));
  }
  String found = NULL;
  foreach (String dir, dirs) {
    String path = %"$dir/$target";
    if (!sources.exists(path)) continue;
    found = path;
    *covered = dir == lib_dir || dir == include_dir;
    break;
  }
  dirs.free();
  return found;
}

static String _resolve_include(
  Compiler compiler, String includer_dir, String target, int angle,
  int *covered) => _resolve_include_dirs(
    compiler.sources, compiler.include_dirs, includer_dir, target, angle,
    covered);

/* Process cache: canonical path ->
   `(ordered-parts hash definitions dependencies)`. A part is a declaration
   Map or an included source path. Dependencies map macro, Lisp, and
   embedded-text paths to a content hash or 1. Entries outlive per-unit
   scopes, so every retained key and value belongs to process_cache_scope. */
static Map process_cache = NULL, static Scope process_cache_scope = NULL;

static void _cache_shutdown(void) {
  Scope.destroy(process_cache_scope);
  process_cache_scope = NULL;
  process_cache = NULL;
}

static Map _process_cache(void) {
  if ((void *) process_cache != NULL) return process_cache;
  Scope.push(&process_cache_scope);
  Scope.shutdown_hook(_cache_shutdown);
  process_cache = {};
  Scope.pop();
  return process_cache;
}

/* A file's entry: collected in this process, or read from its interface. */
static List _entry(Compiler c, String canonical) {
  Var cached = _process_cache()[canonical];
  return cached is void ? _interface_read(c, canonical) : cached;
}

static void _cache_dependency(
  Map dependencies, String path, Var content_hash) {
  _require_retained(path.try_own());
  if (content_hash is <string>)
    _require_retained(content_hash.string().try_own());
  dependencies.merge_translation_dependency(path, content_hash);
}

static void _cache_dependencies(Map dependencies, Map additions) {
  foreach (Var (path, content_hash), additions)
    _cache_dependency(dependencies, path, content_hash);
}

/* An explicit runtime include matters only when the module contributes a
   declaration outside the prelude. Standard runtime includes are no-ops;
   optional x2c modules load from their own interfaces. */
static int _entry_adds_symbols_visit(
  Compiler compiler, List entry, Map globs, Map visited) {
  foreach (Var part, entry.car().list()) {
    if (part is <map>) {
      Map additions = part;
      foreach (Var key, additions.keys()) if (!globs.contains(key)) return 1;
      continue;
    }
    String dependency = part;
    if (visited.contains(dependency)) continue;
    visited[dependency] = 1;
    List resolved = _entry(compiler, dependency);
    if (resolved &&
        _entry_adds_symbols_visit(compiler, resolved, globs, visited))
      return 1;
  }
  return 0;
}

static int _entry_adds_symbols(Compiler compiler, List entry, Map globs) =>
  _entry_adds_symbols_visit(compiler, entry, globs, {});

/* Replay declaration maps and includes in their recorded source order.
   visited counts each included file's declarations, dependencies, and
   function definitions once per translation unit. In-memory and interface
   entries have the same shape and take this same path. */
static void _replay_cached(
  Compiler compiler, List entry, Map globs, Map visited) {
  foreach (Var definition, entry.caddr()) compiler.fn_defs[definition] = 1;
  /* Parsing this file read these macro and Lisp files. They are prerequisites
     of every unit that reaches it, not only of the one that parsed it. */
  compiler.merge_translation_dependencies(entry[3]);
  foreach (Var part, entry.car()) {
    if (part is <map>) {
      globs.merge(part);
      compiler.merge_source_declarations(globs, part);
      continue;
    }
    String dep_path = part;
    compiler.add_translation_dependency(dep_path);
    if (visited.contains(dep_path)) continue;
    visited[dep_path] = 1;
    List resolved = _entry(compiler, dep_path);
    if (resolved) _replay_cached(compiler, resolved, globs, visited);
    else _walk_cold(compiler, dep_path, dep_path, globs, visited);
  }
}

/* Read an include's text, reporting an unreadable target as a driver error. */
static String _include_text(Compiler c, String target, String path) {
  String text = NULL;
  if (!c.read_source(path, &text))
    c.report_error(<driver>, "cannot read include", c.token,
                   %("stage: collect" "include: $target" "path: $path"));
  return text;
}

/* Walk one included file cold into globs; its entry joins the cache. */
static void _walk_cold(
  Compiler c, String target, String canonical, Map globs, Map visited) {
  String text = _include_text(c, target, canonical);
  _file(c, canonical, text, Path.dirname(canonical), globs, visited);
}

/* A segment resolves names through cumulative globs but writes declarations
   only to overlay. shallow_parse_overlay expands applicable unit macros under
   semantic transactions, so their committed declarations and protocol rows
   are recorded at this segment's source position. Macro, Lisp, and keyword
   state then returns to the enclosing compiler for the next segment. */
static void _parse_segment(
  Compiler c, String path, String source, String text, int start_line,
  int start_pos, Map globs, Map overlay, Map definitions, Map dependencies,
  int *private) {
  Compiler shadow = Compiler.new_shared(c);
  defer c.close_child(shadow);
  /* A package renames what it declares, not what it includes. A C header's
     types and enumerators keep their upstream spelling, so a public method
     over one of them still names a type the header defines. */
  int unit = x2c_source_file(path);
  if (!unit) shadow.package = NULL;
  shadow.filename = path;
  shadow.source_private = *private;
  shadow.take_unit_state(c);
  shadow.tokenize(text);
  shadow.text = source;
  if (c.source_facts) c.source_texts[Path.absolute(path)] = source;
  for (size_t i = 0; i < shadow.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) shadow.tokenizer.tokens)[i];
    token.line += start_line - 1;
    token.pos += start_pos;
  }
  shadow.shallow_parse_overlay(globs, overlay);
  shadow.return_unit_state(c);
  if (unit) {
    c.fn_defs.merge(shadow.fn_defs);
    definitions.merge(shadow.fn_defs);
  }
  /* A segment's import collects the package once for the whole unit, so its
     files are prerequisites of the unit rather than of this shadow, and they
     go on this file's cache entry so a later replay of it records them too. */
  _cache_dependencies(dependencies, shadow.deps);
  c.merge_translation_dependencies(shadow.deps);
  *private = shadow.source_private;
  globs.merge(overlay);
  c.merge_source_declarations(globs, overlay);
}

/* Append one segment's nonempty overlay before the following include. */
static void _flush_segment(
  Compiler compiler, String path, String source, String text, int start_line,
  int start_pos, Map globs, Array parts, Map definitions, Map dependencies,
  int *private) {
  if (!text || !*text) return;
  Scope.push(&process_cache_scope);
  Map overlay = {};
  Scope.pop();
  _parse_segment(
    compiler, path, source, text, start_line, start_pos,
    globs, overlay, definitions, dependencies, private);
  if (overlay.len()) {
    Var overlay_var = overlay;
    parts.push(overlay_var);
  }
}

/* Resolve and splice one include during a file walk. The included file's
   content hash joins the including file's dependencies, so a replayed
   interface is rejected when any file it spliced has changed. */
static void _include(
  Compiler c, String target, int angle, String dir, Map globs,
  Map visited, Array parts, Map dependencies) {
  int covered = 0;
  String path = _resolve_include(c, dir, target, angle, &covered);
  if (!path) return;
  if (covered && !x2c_source_file(path)) return;
  String canonical = _canonical_path(path);
  List entry = _entry(c, canonical);
  /* The entry records every include, so it does not depend on what the unit
     that first walked this file had already seen. */
  parts.push(canonical);
  if (!covered || c.runtime_hdrs || !entry ||
      _entry_adds_symbols(c, entry, globs)) {
    c.add_translation_dependency(canonical);
    if (!visited.contains(canonical)) {
      visited[canonical] = 1;
      if (entry) _replay_cached(c, entry, globs, visited);
      else _walk_cold(c, target, canonical, globs, visited);
    }
  }
  /* A file still being walked, as in an include cycle, has no entry yet. */
  Var walked = _process_cache()[canonical];
  String content_hash = walked is void
    ? "%08x".printf(_include_text(c, target, canonical).hash())
    : walked.list().cadr();
  _cache_dependency(dependencies, canonical, content_hash);
}

static void _require_retained(int owned) {
  if (owned) return;
  fprintf(stderr, "x2c: could not retain process cache entry\n");
  abort();
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
  if ((void *) contribution == NULL) return;
  List key = %($name), marker_key = %("generated-protocol" $name);
  List marker = %(generated);
  _require_retained(key.try_own());
  _require_retained(marker_key.try_own());
  _require_retained(marker.try_own());
  _require_retained(signature.try_own());
  contribution[key] = signature;
  contribution[marker_key] = marker;
}

/* Record a cold walk under canonical path identity. Segment overlays and
   included canonical paths enter parts in source order, while source-private
   state carries only between segments of this file; every included file
   starts its own visibility state. The first cold visit fixes a header's
   contribution for later units, so its public declarations must not depend on
   unit-local names visible before the include. */
static void _file(
  Compiler c, String path, String text, String dir, Map globs,
  Map visited) {
  Map enclosing_aliases = c.kw_aliases, enclosing_alias_imports = c.kw_seen;
  $let(c.declaration_effects, NULL) {
    c.kw_aliases = {};
    c.kw_seen = {};
    Array parts = [];
    Scope.push(&process_cache_scope);
    Map dependencies = {};
    Scope.pop();
    Map definitions = {}, int private = 0;
    String content_hash = "%08x".printf(text.hash());
    /* Scanned tokens place directives outside strings and comments. A
       segment ends before an include and the next begins after it. */
    Tokenizer tokenizer = Tokenizer.new(text);
    tokenizer.scan();
    Token first = tokenizer.tokens;
    int segment_line = 1, segment_position = 0;
    for (Token token = first; token.type != <eof>; token++) {
      int angle = 0;
      String target = token.type == <preproc> && _starts_line(first, token)
        ? preproc_include_target(token.text, &angle)
        : NULL;
      if (!target) continue;
      _flush_segment(
        c, path, text, text[segment_position:token.pos], segment_line,
        segment_position, globs, parts, definitions, dependencies, &private);
      _include(c, target, angle, dir, globs, visited, parts, dependencies);
      Token next = token + 1;
      segment_line = next.line;
      segment_position = next.pos;
    }
    _flush_segment(
      c, path, text, text[segment_position:], segment_line, segment_position,
      globs, parts, definitions, dependencies, &private);
    Map generated =
      c.select_declaration_defaults(path, globs, parts, definitions);
    if (generated && generated.len()) {
      Scope.push(&process_cache_scope);
      Map retained = generated.copy();
      Scope.pop();
      parts.push(retained);
    }
    List part_list = parts.list_free();
    _require_retained(path.try_own());
    foreach (Var part, part_list) {
      if (part is not <map>) continue;
      Map rows = part;
      foreach (Var (key, value), rows) {
        if (key is <list>) _require_retained(key.list().try_own());
        if (key is <string>)
          _require_retained(key.string().try_own());
        if (value is <list>)
          _require_retained(value.list().try_own());
        if (value is <string>)
          _require_retained(value.string().try_own());
      }
    }
    Array names = [];
    foreach (Var definition, definitions.keys()) names.push(definition);
    names.sort();
    List definition_list = names.list_free();
    List entry = %(
      $part_list $content_hash $definition_list $dependencies
    );
    _require_retained(entry.try_own());
    /* The first walk of a file fixes its contribution. A later walk of the
       same file, such as a unit whose text the prelude already covered,
       does not replace an entry that other units may already have replayed. */
    if (!_process_cache().contains(path)) _process_cache()[path] = entry;
    c.kw_aliases = enclosing_aliases;
    c.kw_seen = enclosing_alias_imports;
  }
}

static String _runtime_text(Compiler c, String runtime) {
  String text = NULL;
  if (!c.read_source(runtime, &text))
    c.report_error(
      <driver>, "cannot read runtime source", c.token,
      %("path: $runtime"));
  return text;
}

/* The prelude contribution is `lib/x2c.x`'s entry: cached in this process,
   read from `lib/x2c.xi` beside a stage build, or walked cold once. */
static List _prelude_entry(Compiler c, String runtime, String canonical) {
  List entry = _entry(c, canonical);
  if (entry) return entry;
  Map scratch = {}, visited = {};
  visited[canonical] = 1;
  _file(
    c, canonical, _runtime_text(c, runtime), Path.dirname(runtime),
    scratch, visited);
  return _process_cache()[canonical];
}

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
  if ((void *) globs == NULL) globs = {};
  c.kw_aliases = NULL;
  c.kw_seen = NULL;
  Map visited = {}, String canonical = _canonical_path(c.filename);
  c.deps = {};
  c.add_translation_dependency(canonical);
  if (c.prelude) {
    String runtime = %"${x2c_get_root()}/lib/x2c.x";
    String runtime_canonical = _canonical_path(runtime);
    visited[runtime_canonical] = 1;
    c.add_translation_dependency(runtime_canonical);
    if (c.runtime_hdrs)
      _file(
        c, runtime_canonical, _runtime_text(c, runtime),
        Path.dirname(runtime), globs, visited);
    else
      _replay_cached(
        c, _prelude_entry(c, runtime, runtime_canonical), globs, visited);
  }
  visited[canonical] = 1;
  _file(
    c, canonical, c.text,
    Path.dirname(c.filename), globs, visited);
  return globs;
}

// package imports

/* Resolve a package name under the registered roots. The entry unit is
   `<root>/<name>/src/<name>.x`, or `<root>/<name>/<name>.x` for the
   single-file layout used by toys and fixtures. */
static String _package_entry(
  Compiler compiler, String name, String *directory) {
  foreach (String package_dir, compiler.package_dirs) {
    String root = %"${_canonical_path(package_dir)}/$name";
    String nested = %"$root/src/$name.x";
    String entry = compiler.sources.exists(nested) ? nested : %"$root/$name.x";
    if (!compiler.sources.exists(entry)) continue;
    if (directory) *directory = root;
    return _canonical_path(entry);
  }
  return NULL;
}

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
  return row && %(protocol adopt declaration-source).contains(row.car());
}

/* The package's `name__` space is visible in the importing unit, and so does
   a C header it publishes: a package renames what it declares, not what it
   includes, so those names cross as including that header gives them.
   Inside the package root an unprefixed x2c key is a static, which
   keeps C internal linkage and stays home; outside it the file escaped the
   declare-time rewrite and its bare names would merge into the consumer's
   one flat namespace. */
static void _package_merge(
  Compiler compiler, String name, String root, String path, Map part,
  Map merged, Token token) {
  String prefix = %"${name}__", int header = !x2c_source_file(path);
  int foreign = !path.startswith(%"$root/");
  foreach (Var (key, value), part) {
    if (key is not <list> || key.is_nil()) continue;
    if (_package_protocol_row(key, value)) {
      merged[key] = value;
      compiler.copy_source_declaration(merged, part, key);
      continue;
    }
    String spelling = _package_key_spelling(key);
    if (!spelling) continue;
    if (header || spelling.startswith(prefix)) {
      merged[key] = value;
      compiler.copy_source_declaration(merged, part, key);
      continue;
    }
    if (!foreign) continue;
    String unit = path.split("/").last();
    String fix = %"below #pragma private, or move it into '$name/src'";
    compiler.report_error(
      <driver>,
      %"package '$name' exposes unprefixed top-level declaration '$spelling'",
      token,
      %( "'$unit' is x2c source outside the package; include it $fix" ));
  }
}

/* Replay one cached entry for its declarations only, recording each package
   file as a dependency of the importing unit. */
static void _package_contributions(
  Compiler compiler, String name, String root, String path, List entry,
  Map merged, Map visited, Token token) {
  compiler.merge_translation_dependencies(entry[3]);
  foreach (Var part, entry.car()) {
    match (%($part)) {
      case %(?(Map declarations)): {
        _package_merge(
          compiler, name, root, path, declarations, merged, token);
        continue;
      }
      case %(?(String dependency)): {
        compiler.add_translation_dependency(dependency);
        if (visited.contains(dependency)) continue;
        visited[dependency] = 1;
        _package_contributions(
          compiler, name, root, dependency,
          _process_cache()[dependency], merged, visited, token);
        continue;
      }
    }
    __builtin_unreachable();
  }
}

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
  if (c.package_roots.contains(name)) return;
  String root = NULL, entry = _package_entry(c, name, &root);
  if (!entry)
    c.report_error(
      <driver>, %"unknown package '$name'", token,
      %( "searched: <root>/$name/src/$name.x, <root>/$name/$name.x" ));
  Compiler package = Compiler.new_shared(c);
  defer c.close_child(package);
  package.package = name;
  package.filename = entry;
  Map globs = c.sym.base_symbols(), visited = {};
  visited[entry] = 1;
  List cached = _entry(c, entry);
  if (cached) _replay_cached(package, cached, globs, visited);
  else {
    String text = NULL;
    if (!package.read_source(entry, &text))
      c.report_error(
        <driver>, %"cannot read package '$name'", token,
        %( "path: $entry" ));
    _file(package, entry, text, Path.dirname(entry), globs, visited);
  }
  c.fn_defs.merge(package.fn_defs);
  Map merged = {}, walked = {};
  walked[entry] = 1;
  c.add_translation_dependency(entry);
  _package_contributions(
    c, name, root, entry, _process_cache()[entry],
    merged, walked, token);
  c.package_roots[name] = root;
  foreach (Var (key, value), merged) {
    c.sym.set(key, value);
    c.copy_source_declaration(c.sym.current_symbols(), merged, key);
  }
}

// unit interfaces

/* A `.xi` interface is one unit's cache entry written beside its generated
   C. Missing, stale, or malformed interfaces are cache misses; the caller
   walks the file cold and installs that result in the process cache. Paths
   inside an interface use `home_portable_path` spellings. */

static String interface_out_dir = NULL, interface_mirror = NULL;

/** Creates the process cache and names the directories searched for `.xi`
    interfaces. `out_dir` is the current translation output directory, or
    NULL. Home files mirror their home-relative path under the compiler's
    stage directory when it runs from `<home>/builds/`, otherwise under the
    home. Call it before opening any translation unit's Context.
*/
void interface_configure(String out_dir) {
  _process_cache();
  interface_out_dir = out_dir;
  String stage = x2c_stage_dir();
  interface_mirror = stage ? stage : x2c_get_root();
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

/** Returns the readable prelude interface path, or NULL when none exists. */
String interface_prelude(void) {
  String runtime = _canonical_path(%"${x2c_get_root()}/lib/x2c.x");
  foreach (String path, _interface_candidates(runtime))
    if (!access(path, R_OK)) return path;
  return NULL;
}

/* Interfaces name the same sources many times, so a process hashes each
   source once. */
static Map source_hashes = NULL, static Lisp interface_reader = NULL;

static void _interface_shutdown(void) {
  Lisp.destroy(interface_reader);
  interface_reader = NULL;
  source_hashes = NULL;
}

static Lisp _interface_lisp(void) {
  if (interface_reader) return interface_reader;
  _process_cache();
  Scope.push(&process_cache_scope);
  interface_reader = Lisp.kernel();
  source_hashes = {};
  Scope.shutdown_hook(_interface_shutdown);
  Scope.pop();
  return interface_reader;
}

static int _hash_matches(Compiler compiler, String path, Var expected) {
  if (expected is not <string>) return 0;
  Var hash = source_hashes[path];
  if (hash is void) {
    String text = NULL;
    try {
      if (!compiler.read_source(path, &text)) return 0;
    }
    catch %(io-fail *): return 0;
    catch %(bad-arg *): return 0;
    catch %(size-limit *): return 0;
    String value = "%08x".printf(text.hash());
    _require_retained(path.try_own());
    _require_retained(value.try_own());
    source_hashes[path] = value;
    hash = value;
  }
  return String.equal(hash, expected);
}

/* Materialize one interface file only after its source path and hash, and
   the content hashes of the includes, macros, Lisp, and embedded text it
   depends on, validate. The entry uses process_cache_scope ownership and the
   same ordered parts representation as a cold walk. */
static List _interface_load(Compiler c, String canonical, String path) {
  String source = NULL;
  File input = fopen(path, "r");
  if (!input) return NULL;
  try source = input.string_close();
  catch %(io-fail *): return NULL;
  unsigned cursor = 0;
  Var record = void;
  Symbol status = 0;
  try status = Lisp.read(_interface_lisp(), source, &cursor, &record);
  catch %(incomplete *): return NULL;
  catch %(malformed *): return NULL;
  if (status != <value> || record is not <list>) return NULL;
  match (record)
    case %(interface 2 ?(String owner) ?(String hash) ?(List stored_parts)
           ?(List definitions) ?(List stored_dependencies)): {
      if (!home_absolute_path(owner).equal(canonical) ||
          !_hash_matches(c, canonical, hash)) return NULL;
      return _interface_entry(
        c, canonical, hash, stored_parts, definitions, stored_dependencies);
    }
  return NULL;
}

/* Rebuild a validated interface's rows as a process cache entry, or return
   NULL when a row is malformed or a dependency has changed. */
static List _interface_entry(
  Compiler c, String canonical, String hash, List stored_parts,
  List definitions, List stored_dependencies) {
  Array parts = [];
  foreach (Var part, stored_parts) {
    if (part is <string>) {
      parts.push(_canonical_path(home_absolute_path(part)));
      continue;
    }
    if (part is not <list>) return NULL;
    Scope.push(&process_cache_scope);
    Map contributions = {};
    Scope.pop();
    foreach (Var row, part.list()) {
      if (row is not <list> || row.list().len() != 2) return NULL;
      List pair = row;
      _require_retained(pair.try_own());
      Var (contribution_key, contribution_value) = pair;
      contributions[contribution_key] = contribution_value;
    }
    Var contributions_var = contributions;
    parts.push(contributions_var);
  }
  Scope.push(&process_cache_scope);
  Map dependencies = {};
  Scope.pop();
  foreach (Var dependency, stored_dependencies) {
    if (dependency is not <list>) return NULL;
    match (dependency.list())
      case %(?(String name) ?content_hash): {
        String dependency_path = _canonical_path(home_absolute_path(name));
        int unhashed =
          content_hash.is_integer() && content_hash.integer() == 1;
        if (!unhashed && !_hash_matches(c, dependency_path, content_hash))
          return NULL;
        _cache_dependency(dependencies, dependency_path, content_hash);
        continue;
      }
    return NULL;
  }
  foreach (Var definition, definitions)
    if (definition is not <string>) return NULL;
  List part_list = parts.list_free();
  List entry = %($part_list $hash $definitions $dependencies);
  _require_retained(canonical.try_own());
  _require_retained(entry.try_own());
  _process_cache()[canonical] = entry;
  return entry;
}

/* Find and validate the interface of one canonical source path. A source
   under inspection through a SourceView never reads interfaces. */
static List _interface_read(Compiler c, String canonical) {
  if (c.source_facts || !interface_mirror) return NULL;
  foreach (String path, _interface_candidates(canonical)) {
    List entry = _interface_load(c, canonical, path);
    if (entry) return entry;
  }
  return NULL;
}

/* A cold walk numbers bindings from wherever the shared counter stands, which
   depends on the files walked before it. An interface renumbers them in order
   of first appearance, keeping equal bindings equal. */
static List _renumber_bindings(List node, Map identities) {
  String spelling = NULL;
  if (binding_identity_try_parts(node, NULL, &spelling)) {
    Var identity = identities.setdefault(node, identities.len() + 1);
    return binding_identity_new(identity, spelling);
  }
  Var child;
  $ast.rewrite_children(
    node, child, _renumber_bindings(child, identities));
}

/* An interface is data in part of the Lisp reader grammar: proper Lists,
   bare Symbols and Atoms, Strings, integers, and floating-point values. A
   loader never evaluates it. An atom that needs quoting, or any other value,
   returns zero. */
static int _write_datum(Buffer out, Var value) {
  if (value is <list>) {
    List list = value;
    out.write_char('(');
    for (List p = list; p; p = p.cdr()) {
      if (p != list) out.write_char(' ');
      if (!_write_datum(out, p.car())) return 0;
    }
    out.write_char(')');
  }
  else if (value.is_atom()) {
    // lib/atom.x owns bare spelling and the reader's Symbol/Atom choice.
    String text = value.str();
    if (Atom.bare_spelling(text)) out.write(text);
    else if (value is <symbol>) out.write(value.repr());  // `<"<<">`
    else return 0;
  }
  else if (value is <string>) out.write(value.repr());
  else if (value.is_integer()) out.printf("%ld", value.integer());
  else if (value.is_floating()) out.printf("%.17g", value.floating());
  else return 0;
  return 1;
}

static int _write_interface_entry(Buffer out, String canonical, List entry) {
  (List cached_parts, Var hash, List definitions, Map cached_dependencies) =
    entry;
  Array parts = [];
  Map identities = {};
  foreach (Var part, cached_parts) {
    if (part is <map>) {
      Array rows = [], Map contributions = part;
      foreach (Var (row_key, row_value), contributions)
        rows.push(%($row_key $row_value));
      rows.sort();
      Var rows_var = _renumber_bindings(rows.list_free(), identities);
      parts.push(rows_var);
      continue;
    }
    parts.push(home_portable_path(part));
  }
  Array dependencies = [];
  foreach (Var (path, content_hash), cached_dependencies)
    dependencies.push(%(${home_portable_path(path)} $content_hash));
  dependencies.sort();
  List dependency_list = dependencies.list_free();
  List part_list = parts.list_free();
  List record = %(
    interface 2 ${home_portable_path(canonical)} $hash
    $part_list $definitions $dependency_list
  );
  if (!_write_datum(out, record)) return 0;
  out.write_char('\n');
  return 1;
}

/** Writes the compiler's own collected contribution to `path`.
    The unit must have collected its symbols; otherwise nothing is written.
    A process-specific sibling is written and renamed into place, so a
    failure leaves any existing interface intact and is reported as an
    `emit` diagnostic.
*/
void interface_write(Compiler compiler, String path) {
  String canonical = _canonical_path(compiler.filename);
  Var cached = _process_cache()[canonical];
  if (cached is void) return;
  Buffer out = $auto(Buffer.new(0));
  long error = 0;
  if (_write_interface_entry(out, canonical, cached)) {
    try {
      file_publish(path, out);
      return;
    }
    catch %(not-found *failure): error = failure.assoc(<errno>);
    catch %(io-fail *failure): error = failure.assoc(<errno>);
  }
  String reason = String.new(strerror((int) error));
  compiler.report_error(
    <emit>, "failed to write interface file", NULL,
    %("file: $path" "reason: $reason"));
}
