/* collect.x -- source-ordered shallow symbol collection and replay

   Raw collection scans includes without running cpp. Each cold walk records
   declaration maps and included paths at their source positions; cache and
   artifact replay consume that same order so declaration precedence and
   generated-name counters do not depend on whether a file was already
   collected.
*/

#pragma once
#include "compiler.x"

#pragma private
#include "buffer.x"
#include "utils.x"
#include "snapshot.x"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

/* Non-include lines yield NULL; `angle` distinguishes <...> from "...". */
static String _preproc_include_target(String text, int *angle) {
  *angle = 0;
  String body = text.strip(" \t\r\n");
  if (!body.startswith("#")) return NULL;
  body = body[1:].lstrip(" \t");
  if (!body.startswith("include")) return NULL;
  body = body.remove_prefix("include").lstrip(" \t");
  if (!body.len()) return NULL;
  char open = body[0];
  if (open != '"' && open != '<') return NULL;
  *angle = open == '<';
  String rest = body[1:], int close = rest.find(*angle ? ">" : "\"");
  return close > 0 ? rest[:close] : NULL;
}

/* Strip comments while preserving directive text and block state. */
static String _directive_line(String line, int *in_comment) {
  int length = line.len(), start = 0;
  if (*in_comment) {
    for (int n = 0; n < length; n++)
      if (line[n] == '*' && n + 1 < length && line[n+1] == '/') {
        *in_comment = 0;
        start = n + 2;
        break;
      }
    if (*in_comment) return NULL;
  }
  Buffer output = NULL;
  for (int n = start; n < length; n++) {
    char ch = line[n];
    if (ch == '"' || ch == '\'') {
      int used = ch == '"' ? scan_c_string(line + n)
                           : scan_c_character(line + n);
      if (used < 0) return line;
      n += used - 1;
      continue;
    }
    if (ch != '/') continue;
    if (n + 1 < length && line[n+1] == '/') {
      if (!output) return line[start:n];
      output.write_len(line + start, n - start);
      return output.str_free();
    }
    if (n + 1 < length && line[n+1] == '*') {
      if (!output) output = Buffer.new(0);
      output.write_len(line + start, n - start);
      *in_comment = 1;
      for (n += 2; n < length; n++)
        if (line[n] == '*' && n + 1 < length && line[n+1] == '/') {
          *in_comment = 0;
          output.write(" ");
          start = ++n + 1;
          break;
        }
      if (*in_comment) return output.str_free();
    }
  }
  if (!output) return line[start:];
  output.write_len(line + start, length - start);
  return output.str_free();
}

/* Unresolvable paths retain the caller's spelling. */
static String _canonical_path(String path) {
  char buffer[PATH_MAX];
  return realpath(path, buffer) ? %"$buffer" : path;
}

// Include targets must be readable regular files.
static int _includable_file(SourceView sources, String path) {
  if (sources) return sources.exists(path);
  struct stat info;
  if (access(path, R_OK) || stat(path, &info)) return 0;
  return S_ISREG(info.st_mode) != 0;
}

/* Canonical process-wide include roots. */
static String _cached_canonical(char *cache, String dir) {
  if (!*cache && !realpath(dir, cache))
    snprintf(cache, PATH_MAX, "%s", (char *) dir);
  return %"$cache";
}

static String _canonical_root(void) {
  static char cache[PATH_MAX];
  return _cached_canonical(cache, x2c_get_root());
}

static String _canonical_lib(void) {
  static char cache[PATH_MAX];
  if (*cache) return %"$cache";
  return _cached_canonical(cache, %"${x2c_get_root()}/lib");
}

static String _canonical_include(void) {
  static char cache[PATH_MAX];
  if (*cache) return %"$cache";
  return _cached_canonical(cache, %"${x2c_get_root()}/include");
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
    return _includable_file(sources, target) ? target : NULL;
  String lib_dir = _canonical_lib(), include_dir = _canonical_include();
  Array dirs = %[];
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
    if (!_includable_file(sources, path)) continue;
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
   `(ordered-parts gensyms hash definitions dependencies)`. A part is a
   declaration Map or an included source path. Dependencies map macro, Lisp,
   and embedded-text paths to a content hash or 1. Entries outlive per-unit
   scopes, so every retained key and value belongs to header_cache_scope. */
static Map header_contributions = NULL, static Scope header_cache_scope = NULL;
static int record_generated_symbols;

static void _cache_shutdown(void) {
  Scope.destroy(header_cache_scope);
  header_cache_scope = NULL;
  header_contributions = NULL;
}

static Map _header_cache(void) {
  if ((void *) header_contributions != NULL) return header_contributions;
  Scope.push(&header_cache_scope);
  Scope.shutdown_hook(_cache_shutdown);
  header_contributions = %{};
  Scope.pop();
  return header_contributions;
}

/** Initializes the process-wide source-collection cache. */
void header_symbols_initialize(void) {
  _header_cache();
}

/** Enables recording of generated public protocol callables.
    Recording remains enabled for subsequent translations in this process.
*/
void header_symbols_begin_generated(void) {
  record_generated_symbols = 1;
}

static void _cache_dependency(
  Map dependencies, String path, Var content_hash) {
  _require_header_cache_owner(path.try_own());
  if (content_hash is <string>)
    _require_header_cache_owner(content_hash.string().try_own());
  dependencies.merge_translation_dependency(path, content_hash);
}

static void _cache_dependencies(Map dependencies, Map additions) {
  foreach (Var (path, content_hash), additions)
    _cache_dependency(dependencies, path, content_hash);
}

/* An explicit runtime include matters only when the module contributes a
   declaration outside the standard snapshot. Standard runtime includes are
   no-ops; optional x2c modules load from the same header artifact. */
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
    Var cached = _header_cache()[dependency];
    List resolved = cached is void ? _artifact_fetch(compiler, dependency)
                                   : cached.list();
    if (resolved &&
        _entry_adds_symbols_visit(compiler, resolved, globs, visited))
      return 1;
  }
  return 0;
}

static int _entry_adds_symbols(Compiler compiler, List entry, Map globs) =>
  _entry_adds_symbols_visit(compiler, entry, globs, %{});

/* Replay declaration maps and includes in their recorded source order.
   visited counts each included file's declarations, dependencies, function
   definitions, and self-only gensym count once per translation unit. In-memory
   and artifact entries have the same shape and take this same path. */
static void _replay_cached(
  Compiler compiler, List entry, Map globs, Map visited) {
  (List parts, int gensyms, Var content_hash, List definitions,
   Map dependencies) = entry;
  (void) content_hash;
  foreach (Var definition, definitions) compiler.fn_defs[definition] = 1;
  /* Parsing this file read these macro and Lisp files. They are prerequisites
     of every unit that reaches it, not only of the one that parsed it. */
  compiler.merge_translation_dependencies(dependencies);
  foreach (Var part, parts) {
    if (part is <map>) {
      Map.merge(globs, part);
      compiler.merge_source_declarations(globs, part);
      continue;
    }
    String dep_path = part;
    compiler.add_translation_dependency(dep_path);
    if (visited.contains(dep_path)) continue;
    visited[dep_path] = 1;
    Var dep_entry = _header_cache()[dep_path];
    List resolved = dep_entry is void ? _artifact_fetch(compiler, dep_path)
                                        : dep_entry.list();
    if (resolved) _replay_cached(compiler, resolved, globs, visited);
  }
  compiler.names.gensym_count += gensyms;
}

/* A segment resolves names through cumulative globs but writes declarations
   only to overlay. shallow_parse_overlay expands applicable unit macros under
   semantic transactions, so their committed declarations and protocol rows
   are recorded at this segment's source position. Macro, Lisp, and keyword
   state then returns to the enclosing compiler for the next segment. */
static void _parse_segment(
  Compiler c, String path, String source, Array lines, int start_line,
  int start_pos, Map globs, Map overlay, Map definitions, Map dependencies,
  int *private) {
  if (!lines.len()) return;
  String text = %"".join(lines);
  lines.clear();
  if (!text || !*text) return;
  Compiler shadow = Compiler.new_shared(c);
  defer c.close_child(shadow);
  /* A package renames what it declares, not what it includes. A C header's
     types and enumerators keep their upstream spelling, so a public method
     over one of them still names a type the header defines. */
  if (!path.endswith(".x")) shadow.package = NULL;
  shadow.filename = path;
  shadow.include_dirs = c.include_dirs;
  shadow.source_private = *private;
  shadow.macros = c.macros;
  shadow.imports = c.imports;
  shadow.kw_aliases = c.kw_aliases;
  shadow.kw_seen = c.kw_seen;
  /* Segments are one translation unit. Let each shadow use the unit's Lisp
     environment, and keep any environment the first importing segment
     creates alive after that shadow is released. */
  shadow.macro_lisp = c.macro_lisp;
  shadow.declaration_effects = c.declaration_effects;
  shadow.borrowed_lisp = shadow.macro_lisp != NULL;
  shadow.tokenize(text);
  shadow.text = source;
  if (c.source_facts) c.source_texts[SourceView.path(path)] = source;
  for (size_t i = 0; i < shadow.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) shadow.tokenizer.tokens)[i];
    token.line += start_line - 1;
    token.pos += start_pos;
  }
  shadow.shallow_parse_overlay(globs, overlay);
  c.macros = shadow.macros;
  c.imports = shadow.imports;
  c.kw_aliases = shadow.kw_aliases;
  c.kw_seen = shadow.kw_seen;
  c.macro_lisp = shadow.macro_lisp;
  c.declaration_effects = shadow.declaration_effects;
  c.declaration_produced |= shadow.declaration_produced;
  shadow.borrowed_lisp = shadow.macro_lisp != NULL;
  if (path.endswith(".x")) {
    Map.merge(c.fn_defs, shadow.fn_defs);
    Map.merge(definitions, shadow.fn_defs);
  }
  /* A segment's import collects the package once for the whole unit, so its
     files are prerequisites of the unit rather than of this shadow, and they
     go on this file's cache entry so a later replay of it records them too. */
  _cache_dependencies(dependencies, shadow.deps);
  c.merge_translation_dependencies(shadow.deps);
  *private = shadow.source_private;
  Map.merge(globs, overlay);
  c.merge_source_declarations(globs, overlay);
}

/* Append one segment's nonempty overlay before the following include and
   return only the generated names minted while parsing that segment. */
static int _flush_segment(
  Compiler compiler, String path, String source, Array segment, int start_line,
  int start_pos, Map globs, Array parts, Map definitions, Map dependencies,
  int *private) {
  if (!segment.len()) return 0;
  Scope.push(&header_cache_scope);
  Map overlay = %{};
  Scope.pop();
  int before = compiler.names.gensym_count;
  _parse_segment(
    compiler, path, source, segment, start_line, start_pos,
    globs, overlay, definitions, dependencies, private);
  if (overlay.len()) {
    Var overlay_var = overlay;
    parts.push(overlay_var);
  }
  return compiler.names.gensym_count - before;
}

/* Resolve and splice one include during a file walk. */
static void _include(
  Compiler c, String target, int angle, String dir, Map globs,
  Map visited, Array parts) {
  int covered = 0;
  String path = _resolve_include(c, dir, target, angle, &covered);
  if (!path) return;
  if (covered && !path.endswith(".x")) return;
  String canonical = _canonical_path(path);
  Var cached = c.source_facts ? void : _header_cache()[canonical];
  List entry = cached is void ? _artifact_fetch(c, canonical)
                              : cached.list();
  if (covered && !c.runtime_hdrs && entry &&
      !_entry_adds_symbols(c, entry, globs))
    return;
  c.add_translation_dependency(canonical);
  if (visited.contains(canonical)) {
    parts.push(canonical);
    return;
  }
  if (entry) {
    visited[canonical] = 1;
    parts.push(canonical);
    _replay_cached(c, entry, globs, visited);
    return;
  }
  String text = NULL;
  if (c.sources) {
    if (!c.read_source(path, &text))
      c.report_error(<driver>, "cannot read include", c.token,
                     %("stage: collect" "include: $target" "path: $path"));
  }
  else {
    File file = NULL;
    try file = path.open("r");
    catch %(not-found *): {
      List notes = %(
        "stage: collect" "include: $target" "path: $path");
      c.report_error(<driver>, "cannot read include", c.token, notes);
    }
    catch %(io-fail *): {
      List notes = %(
        "stage: collect" "include: $target" "path: $path");
      c.report_error(<driver>, %"cannot read include", c.token, notes);
    }
    try text = file.string_close();
    catch %(io-fail *): {
      List notes = %(
        "stage: collect" "include: $target" "path: $path");
      c.report_error(<driver>, %"cannot read include", c.token, notes);
    }
  }
  visited[canonical] = 1;
  parts.push(canonical);
  _file(c, canonical, text, x2c_path_dir(path), globs, visited);
}

static void _require_header_cache_owner(int owned) {
  if (owned) return;
  fprintf(stderr, "x2c: could not retain header cache entry\n");
  abort();
}

/** Records one generated public callable in its source file's cached surface.
    The operation has no effect until generated-symbol recording is enabled.
    The compiler's current file must already have a collected contribution;
    the cache retains `signature`.
*/
void Compiler.record_generated_header_symbol(
  Compiler compiler, String name, Type signature) {
  if (!record_generated_symbols) return;
  String path = _canonical_path(compiler.filename);
  (List parts, int gensyms, Var content_hash, List definitions,
   Map dependencies) = _header_cache()[path];
  (void) gensyms;
  (void) content_hash;
  (void) definitions;
  (void) dependencies;
  Map contribution = NULL;
  foreach (Var part, parts) {
    match (%($part)) {
      case %(?(Map declarations)): {
        contribution = declarations;
        continue;
      }
      case %((!is type string)): continue;
    }
    __builtin_unreachable();
  }
  if ((void *) contribution == NULL) __builtin_unreachable();
  List key = %($name), marker_key = %("generated-protocol" $name);
  List marker = %(generated);
  _require_header_cache_owner(key.try_own());
  _require_header_cache_owner(marker_key.try_own());
  _require_header_cache_owner(marker.try_own());
  _require_header_cache_owner(signature.try_own());
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
  List enclosing_effects = c.declaration_effects;
  c.declaration_effects = NULL;
  defer c.declaration_effects = enclosing_effects;
  c.kw_aliases = %{};
  c.kw_seen = %{};
  Array parts = %[], segment = %[];
  Scope.push(&header_cache_scope);
  Map dependencies = %{};
  Scope.pop();
  Map definitions = %{}, int self_gensyms = 0, in_comment = 0;
  int line_number = 1, byte_position = 0;
  int segment_line = 1, segment_position = 0, private = 0;
  String content_hash = %"%08x".printf(String.hash(text));
  List lines = text.split_lines(1);
  foreach (String line, lines) {
    int angle = 0, String stripped = _directive_line(line, &in_comment);
    String target =
      stripped ? _preproc_include_target(stripped, &angle) : NULL;
    if (!target) {
      segment.push(line);
      line_number++;
      byte_position += line.len();
      continue;
    }
    self_gensyms += _flush_segment(
      c, path, text, segment, segment_line, segment_position,
      globs, parts, definitions, dependencies, &private);
    _include(c, target, angle, dir, globs, visited, parts);
    line_number++;
    byte_position += line.len();
    segment_line = line_number;
    segment_position = byte_position;
  }
  self_gensyms += _flush_segment(
    c, path, text, segment, segment_line, segment_position,
    globs, parts, definitions, dependencies, &private);
  segment.free();
  Map generated = c.select_declaration_defaults(path, globs, parts, definitions);
  if (generated && generated.len()) {
    Scope.push(&header_cache_scope);
    Map retained = generated.copy();
    Scope.pop();
    parts.push(retained);
  }
  List part_list = parts.list_free();
  _require_header_cache_owner(path.try_own());
  _require_header_cache_owner(part_list.try_own());
  foreach (Var part, part_list) {
    if (part is not <map>) continue;
    Map rows = part;
    foreach (Var (key, value), rows) {
      if (key is <list>) _require_header_cache_owner(key.list().try_own());
      if (key is <string>)
        _require_header_cache_owner(key.string().try_own());
      if (value is <list>)
        _require_header_cache_owner(value.list().try_own());
      if (value is <string>)
        _require_header_cache_owner(value.string().try_own());
    }
  }
  Array names = %[];
  foreach (Var definition, definitions.keys()) {
    _require_header_cache_owner(definition.string().try_own());
    names.push(definition);
  }
  names.sort();
  List definition_list = names.list_free();
  _require_header_cache_owner(definition_list.try_own());
  List entry = %(
    $part_list $self_gensyms $content_hash $definition_list $dependencies
  );
  _require_header_cache_owner(entry.try_own());
  _header_cache()[path] = entry;
  c.kw_aliases = enclosing_aliases;
  c.kw_seen = enclosing_alias_imports;
}

/** Collects the current translation unit's declarations into `globs`.
    The compiler must have its filename, text, and include paths prepared.
    `globs` is the base symbol map and is mutated; a null value starts from an
    empty map. The source and raw-include closure merge in source order, and
    the returned map is `globs`. Collection also updates dependencies,
    function definitions, macro state, and the generated-name count. Keyword
    alias maps and seen-name state are file-local and restored when each file
    walk ends.
*/
Map Compiler.collect_symbols(Compiler c, Map globs) {
  if ((void *) globs == NULL) globs = %{};
  c.kw_aliases = NULL;
  c.kw_seen = NULL;
  Map visited = %{}, String canonical = _canonical_path(c.filename);
  c.deps = %{};
  c.add_translation_dependency(canonical);
  if (c.runtime_hdrs && c.prelude) {
    String runtime = %"${x2c_get_root()}/lib/x2c.x";
    String runtime_canonical = _canonical_path(runtime);
    String text = NULL;
    if (c.sources) {
      if (!c.read_source(runtime, &text))
        c.report_error(<driver>, "cannot read runtime source", c.token, NULL);
    }
    else text = runtime.open("r").string_close();
    visited[runtime_canonical] = 1;
    _file(
      c, runtime_canonical, text, x2c_path_dir(runtime),
      globs, visited);
  }
  visited[canonical] = 1;
  _file(
    c, canonical, c.text,
    x2c_path_dir(c.filename), globs, visited);
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
    String entry = _includable_file(compiler.sources, nested)
                 ? nested : %"$root/$name.x";
    if (!_includable_file(compiler.sources, entry)) continue;
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
    String spelling = head.str();
    if (key.cdr() || spelling == "source-node") return NULL;
    return spelling == "source-typedef" ? NULL : spelling;
  }
  if (head == <self>)
    return key.cdr() && !key.cddr() && spelling_value is <string>
         ? spelling_value.str() : NULL;
  if (head != <typedef> && head != <struct> &&
      head != <union> && head != <enum>) return NULL;
  return key.cdr() && spelling_value is <string>
       ? spelling_value.str() : NULL;
}

/* Protocol declarations and adoptions are keyed by source location instead
   of by a spelling, and a package's rows already name its own prefixed
   types, so they cross with the rest of its surface. */
static int _package_protocol_row(List key, Var value) {
  if (key.car() != %"source-node" || value is not <list>) return 0;
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
  String prefix = %"${name}__", int header = !path.endswith(".x");
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
   file as a dependency of the importing unit. Gensym counts belong to the
   collection that produced the entry and are not counted again here. */
static void _package_contributions(
  Compiler compiler, String name, String root, String path, List entry,
  Map merged, Map visited, Token token) {
  (List parts, int gensyms, Var content_hash, List definitions,
   Map dependencies) = entry;
  (void) gensyms;
  (void) content_hash;
  (void) definitions;
  compiler.merge_translation_dependencies(dependencies);
  foreach (Var part, parts) {
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
          _header_cache()[dependency], merged, visited, token);
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
    importing compiler. Cold collection and in-memory replay also merge
    recorded function definitions; persisted artifact entries carry no
    function-definition list. `token` locates lookup and public-surface errors.
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
  package.include_dirs = c.include_dirs;
  Map globs = c.sym.base_symbols(), visited = %{};
  visited[entry] = 1;
  Var cached = c.source_facts ? void : _header_cache()[entry];
  if (cached is void) {
    String text = NULL, int failed = 0;
    if (c.sources) failed = !package.read_source(entry, &text);
    else {
      try text = entry.open("r").string_close();
      catch %(not-found *): failed = 1;
      catch %(io-fail *): failed = 1;
    }
    if (failed)
      c.report_error(
        <driver>, %"cannot read package '$name'", token,
        %( "path: $entry" ));
    _file(package, entry, text, x2c_path_dir(entry), globs, visited);
  }
  else _replay_cached(package, cached, globs, visited);
  Map.merge(c.fn_defs, package.fn_defs);
  Map merged = %{}, walked = %{};
  walked[entry] = 1;
  c.add_translation_dependency(entry);
  _package_contributions(
    c, name, root, entry, _header_cache()[entry],
    merged, walked, token);
  c.package_roots[name] = root;
  foreach (Var (key, value), merged) {
    c.sym.set(key, value);
    c.copy_source_declaration(c.sym.current_symbols(), merged, key);
  }
}

// persistent header artifacts

/* Missing or stale optional artifacts are cache misses. */

static String _root_relative(String path) {
  String prefix = %"${_canonical_root()}/";
  if (!path.startswith(prefix)) return NULL;
  return path[prefix.len():];
}

static String _snapshot_content_hash(void) {
  String path = %"${x2c_get_root()}/etc/symbols.xlisp";
  File file = fopen(path, "r");
  if (!file) return "00000000";
  String text = NULL;
  try text = file.string_close();
  catch %(io-fail *): return "00000000";
  return %"%08x".printf(String.hash(text));
}

/** Writes the portable source-collection cache to `output`.
    The versioned Lisp artifact records repository-relative paths, the supplied
    generated-name base, and the current symbol-snapshot hash. Entries with an
    out-of-root part or dependency are omitted. Returns nonzero when `output`
    has no error and leaves it open.
*/
int header_symbols_write(File output, int gensym_base) {
  Array names = %[];
  foreach (Var key, _header_cache().keys()) {
    String relative = _root_relative(key);
    if (relative) names.push(relative);
  }
  names.sort();
  output.printf(
    "(header-symbols 10 %d \"%s\" (\n", gensym_base,
    _snapshot_content_hash());
  String root = _canonical_root();
  foreach (Var name, names) {
    String relative = name, canonical = %"$root/$relative";
    List entry = _header_cache()[canonical];
    (List cached_parts, Var gensyms, Var hash, List definitions,
     Map cached_dependencies) = entry;
    (void) definitions;
    Array parts = %[], int portable = 1;
    foreach (Var part, cached_parts) {
      if (part is <map>) {
        Array rows = %[], Map contributions = part;
        foreach (Var (row_key, row_value), contributions)
          rows.push(%($row_key $row_value));
        rows.sort();
        Var rows_var = rows.list_free();
        parts.push(rows_var);
        continue;
      }
      String part_relative = _root_relative(part);
      if (!part_relative) {
        portable = 0;
        break;
      }
      parts.push(part_relative);
    }
    Array dependencies = %[];
    foreach (Var (path, content_hash), cached_dependencies) {
      String relative_path = _root_relative(path);
      if (!relative_path) {
        portable = 0;
        break;
      }
      dependencies.push(%($relative_path $content_hash));
    }
    dependencies.sort();
    List dependency_list = dependencies.list_free();
    List part_list = parts.list_free();
    if (!portable) continue;
    List record = %(
      $relative $hash $gensyms $part_list $dependency_list
    );
    output.puts("  ");
    if (!snapshot_write_var(output, record)) return 0;
    output.putc('\n');
  }
  names.free();
  output.puts("))\n");
  return !output.error();
}

/* Raw artifact rows are indexed by repository-relative path and parsed only
   when collection requests them. artifact_loading breaks include cycles. A
   row is removed before validation, so a malformed or stale row becomes a
   raw-artifact miss for the remainder of the current open. Its caller performs
   a cold walk and installs that result in the process cache. Successfully
   materialized artifact entries move there directly. */
static Map artifact_index = NULL, artifact_loading = NULL;
static Lisp artifact_reader = NULL;

static void _artifact_shutdown(void) {
  Lisp.destroy(artifact_reader);
  artifact_reader = NULL;
  artifact_index = NULL;
  artifact_loading = NULL;
}

/** Opens a compatible source-collection artifact for lazy replay.
    Returns the number of indexed rows, or zero when the file is absent,
    unreadable, empty, or incompatible. A nonnegative `gensym_base` must match
    the artifact header; compatibility also requires the current symbol
    snapshot hash. Raw rows remain indexed until fetched, rejected, or replaced
    by a later open; materialized rows move to the process-wide cache.
*/
int header_symbols_open(String path, int gensym_base) {
  File input = fopen(path, "r");
  if (!input) return 0;
  String source = NULL;
  try source = input.string_close();
  catch %(io-fail *): return 0;
  if (!source) return 0;
  List lines = source.split_lines(0);
  if (!lines) return 0;
  String first = lines.car(), suffix = %"\"${_snapshot_content_hash()}\" (";
  if (!first.startswith("(header-symbols 10 ") || !first.endswith(suffix))
    return 0;
  if (gensym_base >= 0) {
    String expected = %"(header-symbols 10 $gensym_base $suffix";
    if (!String.equal(first, expected)) return 0;
  }
  _header_cache();  // materializes the cache scope and its shutdown hook
  Scope.push(&header_cache_scope);
  artifact_index = %{};
  artifact_loading = %{};
  if (!artifact_reader) {
    artifact_reader = Lisp.new_bare();
    Scope.shutdown_hook(_artifact_shutdown);
  }
  Scope.pop();
  foreach (String line, lines.cdr()) {
    int open_quote = line.find("\"");
    if (open_quote < 0) continue;
    int close_quote = line.find_within("\"", open_quote + 1, -1);
    if (close_quote < 0) continue;
    String relative = line[open_quote + 1:close_quote];
    artifact_index[relative] = line;
  }
  return (int) artifact_index.len();
}

/** Returns whether the active source-collection artifact has indexed rows.
    Translation depfiles use this result because every unit translated while
    the artifact is active depends on it, even if the unit reads no row.
*/
int header_symbols_active(void) =>
  artifact_index && artifact_index.len() ? 1 : 0;

static List _artifact_reject(String relative) {
  artifact_loading.del(relative);
  return NULL;
}

/* Materialize one indexed artifact entry only after its source hash, included
   entries, and macro, Lisp, and embedded-text dependencies validate. The
   reconstructed entry uses header_cache_scope ownership and the same ordered
   parts representation as a cold walk. */
static List _artifact_fetch(Compiler compiler, String canonical) {
  if (compiler.source_facts || (void *) artifact_index == NULL) return NULL;
  Var cached = _header_cache()[canonical];
  if (cached is not void) return cached;
  String relative = _root_relative(canonical);
  if (!relative) return NULL;
  if (artifact_loading.contains(relative)) return %(artifact-pending);
  Var raw = artifact_index[relative];
  if (raw is void) return NULL;
  // Dropping the raw row prevents a second parse and compatibility decision.
  artifact_index.del(relative);
  unsigned cursor = 0;
  Var record = void;
  Symbol status = 0;
  try {
    status = Lisp.read(artifact_reader, raw, &cursor, &record);
  }
  catch %(incomplete *): return NULL;
  catch %(malformed *): return NULL;
  if (status != <value> || record is not <list>) return NULL;
  List fields = record;
  if (fields.len() != 5) return NULL;
  Var (
    stored_relative, expected_hash, gensyms, parts_value,
    dependencies_value) = fields;
  (void) stored_relative;
  if (parts_value is not <list> || dependencies_value is not <list>)
    return NULL;
  artifact_loading[relative] = 1;
  String root = _canonical_root(), path = %"$root/$relative";
  String text = NULL;
  if (!compiler.read_source(path, &text)) return _artifact_reject(relative);
  String current = %"%08x".printf(String.hash(text));
  if (!String.equal(current, expected_hash)) return _artifact_reject(relative);
  Array parts = %[], List stored_parts = parts_value;
  foreach (Var part, stored_parts) {
    if (part is <string>) {
      String dep_full = %"$root/${part.string()}";
      String dep_canonical = _canonical_path(dep_full);
      if (!_artifact_fetch(compiler, dep_canonical))
        return _artifact_reject(relative);
      parts.push(dep_canonical);
      continue;
    }
    if (part is not <list>) return _artifact_reject(relative);
    Scope.push(&header_cache_scope);
    Map contributions = %{};
    Scope.pop();
    foreach (Var row, part.list()) {
      if (row is not <list> || row.list().len() != 2)
        return _artifact_reject(relative);
      List pair = row;
      _require_header_cache_owner(pair.try_own());
      Var (contribution_key, contribution_value) = pair;
      contributions[contribution_key] = contribution_value;
    }
    Var contributions_var = contributions;
    parts.push(contributions_var);
  }
  List part_list = parts.list_free();
  Scope.push(&header_cache_scope);
  Map dependencies = %{};
  Scope.pop();
  List stored_dependencies = dependencies_value;
  foreach (Var dependency, stored_dependencies) {
    if (dependency is not <list> || dependency.list().len() != 2)
      return _artifact_reject(relative);
    List row = dependency;
    Var (dependency_name, content_hash) = row;
    if (dependency_name is not <string>) return _artifact_reject(relative);
    String dependency_path = _canonical_path(
      %"$root/${dependency_name.string()}");
    if (content_hash.is_integer() && content_hash.integer() == 1) {
      _cache_dependency(dependencies, dependency_path, content_hash);
      continue;
    }
    if (content_hash is not <string>) return _artifact_reject(relative);
    String dependency_text = NULL;
    try {
      if (!compiler.read_source(dependency_path, &dependency_text))
        return _artifact_reject(relative);
    }
    catch %(io-fail *): return _artifact_reject(relative);
    catch %(bad-arg *): return _artifact_reject(relative);
    catch %(size-limit *): return _artifact_reject(relative);
    String hash = %"%08x".printf(String.hash(dependency_text));
    if (!String.equal(hash, content_hash)) return _artifact_reject(relative);
    _cache_dependency(dependencies, dependency_path, content_hash);
  }
  List definitions = NULL;
  List entry = %(
    $part_list $gensyms $expected_hash $definitions
    $dependencies
  );
  _require_header_cache_owner(canonical.try_own());
  _require_header_cache_owner(entry.try_own());
  _header_cache()[canonical] = entry;
  artifact_loading.del(relative);
  return entry;
}
