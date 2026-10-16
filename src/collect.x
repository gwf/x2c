/*  collect.x -- source-ordered shallow symbol collection and replay

    Raw collection scans includes without running cpp. Each cold walk
    records declaration maps and included paths at their source positions;
    cache and interface replay consume that same order so declaration
    precedence does not depend on whether a file was already collected. A
    translated unit writes its own contribution beside its generated C as a
    `.xi` interface, and the runtime prelude is `lib/x2c.xi`. The compiler's
    own prelude components are linked into it as the records their
    interfaces would hold.
*/

#pragma once
#include "compiler.x"

#include "ast-rewrite.x"
#include "buffer.x"
#include "datum.x"
#include "utils.x"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// diagnostics

static macro Stmt $report.driver.runtime_read(Expr $c, Expr $runtime) {
  $c.report_error(
    <driver>,
    "cannot read runtime source",
    $c.token, %("path: ${$runtime}"));
}

static macro Stmt $report.driver.include_read(
  Expr $c, Expr $target, Expr $path) {
  $c.report_error(
    <driver>,
    "cannot read include",
    $c.token, %("stage: collect" "include: ${$target}" "path: ${$path}"));
}

static macro Stmt $report.driver.package_unknown(
  Expr $c, Expr $site, Expr $name) {
  $c.report_error(
    <driver>,
    %"unknown package '${$name}'",
    $site, %( "searched: <root>/${$name}/src/${$name}.{x,xp}, <root>/${$name}/${$name}.{x,xp}" ));
}

static macro Stmt $report.driver.package_read(
  Expr $c, Expr $site, Expr $package, Expr $entry) {
  $c.report_error(
    <driver>,
    %"cannot read package '${$package.package}'",
    $site, %( "path: ${$entry}" ));
}

static macro Stmt $report.driver.package_prefix(
  Expr $c, Expr $site, Expr $name, Expr $spelling, Expr $unit, Expr $fix) {
  $c.report_error(
    <driver>,
    %"package '${$name}' exposes unprefixed top-level declaration '${$spelling}'",
    $site, %( "'${$unit}' is x2c source outside the package; include it ${$fix}" ));
}

static macro Stmt $report.driver.module_block(Expr $c, Expr $site) {
  $c.report_error(
    <driver>,
    "malformed module block",
    $site, %("a module block lists member paths as strings, separated by"
    "commas, between braces"));
}

static macro Stmt $report.driver.module_second(Expr $c, Expr $site) {
  $c.report_error(
    <driver>,
    "a file holds one module block",
    $site, NULL);
}

static macro Stmt $report.driver.module_member(
  Expr $c, Expr $site, Expr $member, Expr $stem) {
  $c.report_error(
    <driver>,
    %"module member '${$member}' is outside '${$stem}/'",
    $site, %("a member lies under the companion directory of the file that"
    "names it"));
}

static macro Stmt $report.driver.module_prefix(
  Expr $c, Expr $site, Expr $member, Expr $other) {
  $c.report_error(
    <driver>,
    %"module member '${$member}' takes the static prefix of '${$other}'",
    $site, %("a file's statics take its path with each non-identifier"
    "character made '_' and trailing '_' dropped, then '___'; rename one of"
    "the files"));
}

static macro Stmt $report.driver.module_read(
  Expr $c, Expr $site, Expr $path) {
  $c.report_error(
    <driver>,
    "cannot read module member",
    $site, %("path: ${$path}"));
}

static macro Stmt $report.driver.module_cycle(
  Expr $c, Expr $site, Expr $member, Expr $path) {
  $c.report_error(
    <driver>,
    %"module member '${$member}' is already being spliced",
    $site, %("path: ${$path}"));
}

static macro Stmt $report.emit.interface_write(Expr $c) {
  $c.report_error(
    <emit>,
    "failed to write interface file",
    NULL, NULL);
}

static macro Stmt $report.type.loaded_declaration(
  Expr $c, Expr $name, Expr $path) {
  $c.report_error(
    <type>, %"conflicting native declaration: ${$name}", $c.token,
    %("provider: ${$path}"));
}

// the process cache

/* Process cache: canonical path ->
   `(ordered-parts hash definitions dependencies include-roots)`.
   A part is a declaration Map or an included source path. Dependencies
   map macro, Lisp, and embedded-text paths to a
   content hash or 1. Entries
   outlive per-unit scopes, so every retained key and value belongs to
   process_cache_scope. */
static Map process_cache = NULL, static Scope process_cache_scope = NULL;

/* Paths whose entries a later unit collects again: those collected without
   their declaration defaults while the shared compile-time session was
   being filled, and those a project meta build collected with placeholders
   for its meta calls. */
static Map provisional_entries = NULL;

/* Files collected cold in this process whose entries declare adoptions and
   do not yet record their conformances. */
static Map cold_providers = NULL;

/* Each entry's declared function names; see `_declared_functions`. */
static Map declared_functions = NULL;

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
  provisional_entries = NULL;
  cold_providers = NULL;
  declared_functions = NULL;
  linked_records = NULL;
}

static Map _cache_map(void) {
  $scope(&process_cache_scope) return {};
}

static Map _cache_copy(Map map) {
  $scope(&process_cache_scope) return map.copy();
}

/* A file's entry: collected in this process, or read from its interface. */
static List _entry(Compiler c, String canonical) {
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
static List _collection_entry(Compiler c, String path) {
  List entry = _entry(c, path);
  if (!entry || path in c.collection_native_files) return entry;
  foreach (Var part, entry.car())
    if (part is <map> && %("collection-native") in part.map()) {
      _process_cache().del(path);
      return NULL;
    }
  return entry;
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
  c.kw_aliases = {};
  Map visited = {}, String canonical = _canonical_path(c.filename);
  c.deps = {};
  c.add_translation_dependency(canonical);
  if (c.prelude) _add_prelude(c, globs, visited);
  /* The prelude needs this file's signatures to close include cycles.
     Its own definitions must not suppress fresh declaration defaults.
     Keep type rows: public inline bodies can promote imported families. */
  if (canonical in visited)
    foreach (Var name, _entry(c, canonical).caddr()) {
      globs.del(%($name));
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

/* Builtin components contribute compile-time definitions beside the runtime
   prelude, with the shared source forms they recognize. They do not add
   compiler headers to a user's generated C. Their includes still declare
   into every unit, so they include no module outside `lib/x2c.x` with a
   public inline function, such as `lib/type.x`: a unit calling one would
   declare it without a definition. */
/** Returns the compiler-owned prelude sources relative to its home. Their
    runtime implementations are already linked into the shipped binaries. */
List Compiler.prelude_sources(void) => %(
  "lib/x2c.x" "src/grammar.x" "src/component-access.x" "src/component-try.x"
  "src/component-delegate.x" "src/component-literals.x"
  "src/component-printf.x" "src/component-operators.x"
  "src/component-raise.x" "src/component-match.x"
  "src/component-interpolation.x" "src/component-destructuring.x"
  "src/component-lambdas.x"
  "src/component-protocols.x" "src/component-string-switch.x");

/** Reports whether the canonical `path` is a compiler prelude source. */
int Compiler.is_prelude_source(String path) =>
  Compiler.portable_path(path) in Compiler.prelude_sources();

static void _add_prelude(Compiler c, Map globs, Map visited) {
  foreach (String source, Compiler.prelude_sources()) {
    String path = %"${x2c_get_root()}/$source";
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
      $let(c.builtin_defs, 1)
        _replay_cached(c, entry, canonical, globs, visited, NULL);
    }
  }
}

/* A prelude source's entry: cached in this process, linked into the
   compiler, read from its interface beside a stage build, or walked cold
   once. */
static List _prelude_entry(
  Compiler c, String runtime, String canonical) {
  List entry = _entry(c, canonical);
  if (entry) return entry;
  Map scratch = {}, visited = {};
  visited[canonical] = 1;
  _walk_apart(c, canonical, _runtime_text(c, runtime), scratch, visited);
  return _process_cache()[canonical];
}

static String _runtime_text(Compiler c, String runtime) {
  String text = NULL;
  if (c.read_source(runtime, text)) return text;
  $report.driver.runtime_read(c, runtime);
}

/* Rows enter the unit's symbols and its source declarations together. */
static void _merge_rows(Compiler c, Map globs, Map rows) {
  globs.merge(rows);
  c.merge_source_declarations(globs, rows);
}

// module blocks

/* Assembles one text from a module's files. `line` is the text line that
   the next byte written begins. `path` and `text` are the file being
   appended, and `prefix` is its directory relative to the entry's, or NULL
   for the entry. `file_prefix` begins the spellings of that file's statics,
   and `prefixes` maps each file prefix taken to the name of its file.
   `root` is the entry's resolved companion directory. `splicing` holds
   the resolved paths of the files being appended. */
static typedef struct Splice {
  Compiler c, Buffer out, Array markers, Map members, splicing, prefixes;
  int line;
  String path, text, prefix, file_prefix, root;
} Splice;

/** Returns the x2c source at `path`, whose own text is `text`, with its
    file-scope `module` block replaced by the text of each member it names,
    in order, or NULL when the text has no block. A member lies under the
    companion directory of the file that names it, `NAME/` beside `NAME.x`,
    and its own block is spliced in turn. A member's quoted include of a
    file beside it is spelled from the entry's directory, so it names the
    same file there.
*/
ModuleSource Compiler.module_source(Compiler c, String path, String text) {
  if (!_spells_block(text)) return NULL;
  Buffer out = $auto(Buffer.new(0));
  Splice s = {
    .c = c, .out = out, .markers = [], .members = {}, .splicing = {},
    .prefixes = {}, .line = 1,
    .root = Path.absolute(Path.join(Path.dirname(path), Path.stem(path)))};
  s.splicing[Path.absolute(path)] = 1;
  String own = _file_prefix(Path.stem(path));
  s.prefixes[own] = Path.basename(path);
  if (!_file(s, path, text, NULL, own)) return NULL;
  ModuleSource source = Scope.calloc(1, sizeof(struct ModuleSource));
  *source = (struct ModuleSource) {
    .text = s.out.str(), .own = text, .markers = s.markers,
    .members = s.members};
  return source;
}

/* The token scan decides whether `module` opens a block, including when
   comments separate it from its brace. */
static int _spells_block(const char *text) =>
  text && strstr(text, "module");

/* Appends a file with its block spliced and reports whether it had one.
   Each file's text is marked as its own, so its rows carry its file
   prefix. Diagnostics locate the block in this file. */
static int _file(
  Splice &s, String path, String text, String prefix, String file_prefix) {
  $let(s.path, path) $let(s.text, text) $let(s.prefix, prefix)
  $let(s.file_prefix, file_prefix)
  $let(s.c.filename, path) $let(s.c.text, text)
  $let(s.c.line_markers, NULL) {
    _mark(s, 1, 0);
    Token block = _block(s), close = NULL;
    if (!block) {
      _own(s, 0, text.len(), 1);
      return 0;
    }
    List members = _members(s, block, close);
    _own(s, 0, block.pos, 1);
    _end_line(s);
    foreach (String spelling, members) _member(s, spelling, block);
    _mark(s, close.line, close.pos + 1);
    _own(s, close.pos + 1, text.len(), close.line);
    return 1;
  }
}

/* The `module` that opens the file's file-scope block, or NULL. The word
   opens a block where `{` follows it and no word precedes it, so
   `struct module {` declares a tag. */
static Token _block(Splice &s) {
  if (!_spells_block(s.text)) return NULL;
  Tokenizer tokenizer = Tokenizer.new(s.text, <x2c>);
  tokenizer.layout = Path.is_layout_source(s.path);
  tokenizer.scan();
  Compiler scan = Scope.calloc(1, sizeof(struct Compiler));
  scan.tokenizer = tokenizer;
  scan.scan_conditionals();
  Token block = NULL, previous = NULL;
  int depth = 0;
  for (Token token = Token.skip_trivia(tokenizer.tokens);
       token.type != <eof>; token = Token.skip_trivia(token + 1)) {
    if (!depth && token.text == "module" &&
        Token.skip_trivia(token + 1).type == <"{"> &&
        !(previous && _is_word(previous.text))) {
      if (block) $report.driver.module_second(s.c, token);
      block = token;
    }
    if (token.type == <"}">) depth--;
    else if (token.type.str().endswith("{")) depth++;
    previous = token;
  }
  return block;
}

static int _is_word(String text) =>
  isalnum((unsigned char) text[0]) || text[0] == '_';

/* The member paths of the block `block` opens, whose closing brace becomes
   `close`. */
static List _members(Splice &s, Token block, Token &close) {
  Array members = [];
  Token token = Token.skip_trivia(Token.skip_trivia(block + 1) + 1);
  while (token.type != <"}">) {
    if (token.type != <"lit-char*"> || token.text[0] != '"')
      $report.driver.module_block(s.c, token);
    members.push(token.text[1:token.len - 1].unescape());
    token = Token.skip_trivia(token + 1);
    if (token.type == <",">) token = Token.skip_trivia(token + 1);
    else if (token.type != <"}">) $report.driver.module_block(s.c, token);
  }
  close = token;
  return members.list_free();
}

/* Appends the member `spelling` that the file's block at `site` names. The
   member's resolved location, with links followed, must lie in the
   resolved companion directory, and a file being spliced cannot be spliced
   again inside itself. */
static void _member(Splice &s, String spelling, Token site) {
  String stem = Path.stem(s.path), dir = Path.dirname(s.path), text = NULL;
  String path = dir == "." ? spelling : Path.join(dir, spelling);
  String companion = Path.absolute(Path.join(dir, stem));
  String resolved = Path.absolute(path);
  if (!%"$resolved/".startswith(%"$companion/"))
    $report.driver.module_member(s.c, site, spelling, stem);
  if (resolved in s.splicing)
    $report.driver.module_cycle(s.c, site, spelling, resolved);
  if (!s.c.read_source(path, text))
    $report.driver.module_read(s.c, site, path);
  s.members[_canonical_path(path)] = _content_hash(text);
  String prefix = s.prefix ? Path.join(s.prefix, spelling) : spelling;
  String relative = resolved[s.root.len() + 1:];
  String own = _file_prefix(
    Path.join(Path.dirname(relative), Path.stem(relative)));
  if (own in s.prefixes)
    $report.driver.module_prefix(s.c, site, spelling, s.prefixes[own]);
  s.prefixes[own] = spelling;
  s.splicing[resolved] = 1;
  _file(s, path, text, Path.dirname(prefix), own);
  s.splicing.del(resolved);
  _end_line(s);
}

/* The prefix of a file's statics: its path under the entry's companion
   directory, or the entry's stem, without the extension, with each
   character that cannot continue a C identifier made `_` and trailing `_`
   dropped, then `___`. The spelling starts with `f`, its length, and `_`.
   Dropping trailing underscores keeps `foo_` and `foo` on one prefix,
   so their statics cannot meet past the separator unreported. A package
   prefix ends in `__`, so a package entry's statics never share a spelling
   with the package's public names. A leading digit gets a leading `x`,
   since C reserves file-scope names that begin with `_`. */
static String _file_prefix(String path) {
  if (path.startswith("./")) path = path[2:];
  Buffer spelling = $auto(Buffer.new(0));
  if (isdigit((unsigned char) path[0])) spelling.write_char('x');
  foreach (char ch, path)
    spelling.write_char(isalnum((unsigned char) ch) ? ch : '_');
  String stem = spelling;
  int keep = stem.len();
  while (keep > 1 && stem[keep - 1] == '_') keep--;
  return %"f${keep}_${stem[:keep]}___";
}

/* Appends the file's text from byte `start` to `end`, which begins its
   line `line`. A member's include of a file beside it moves under its
   prefix. */
static void _own(Splice &s, int start, int end, int line) {
  if (start == end) return;
  const char *run = s.text + start, *limit = s.text + end;
  if (s.prefix)
    for (const char *at = run; at < limit; line++) {
      const char *stop = memchr(at, '\n', limit - at);
      stop = stop ? stop + 1 : limit;
      String moved = _moved_include(s, at, stop);
      if (moved) {
        _write(s, run, at);
        _write(s, moved, (const char *) moved + moved.len());
        _mark(s, line + 1, stop - (const char *) s.text);
        run = stop;
      }
      at = stop;
    }
  _write(s, run, limit);
}

/* The line from `at` to `stop` with its quoted include of a file beside
   this one spelled under the prefix, or NULL for any other line. */
static String _moved_include(
  Splice &s, const char *at, const char *stop) {
  const char *hash = at + strspn(at, " \t");
  if (hash >= stop || *hash != '#') return NULL;
  int angle = 0;
  String target =
    Compiler.preproc_include_target(String.new_len(hash, stop - hash), angle);
  if (!target || angle || target.startswith("/") ||
      !s.c.sources.exists(%"${Path.dirname(s.path)}/$target")) return NULL;
  return String.new_len(at, stop - at).replace(
    %"\"$target\"", %"\"${s.prefix}/$target\"");
}

/* From here on the text comes from this file, at its line `line` and byte
   `offset`, continuing that line's text before `offset`. */
static void _mark(Splice &s, int line, int offset) {
  int start = offset;
  while (start > 0 && s.text[start - 1] != '\n') start--;
  String before = s.text[start:offset];
  s.markers.push(
    %(${(int) s.out.len()} ${s.line} ${s.path} $line $offset $before
      ${s.file_prefix}));
}

// Each file's text ends its last line before the next file's begins.
static void _end_line(Splice &s) {
  if (!s.out.len() || s.out[-1] == '\n') return;
  s.out.newline();
  s.line++;
}

static void _write(Splice &s, const char *start, const char *end) {
  s.out.write_len(start, end - start);
  for (const char *ch = start; ch < end; ch++) if (*ch == '\n') s.line++;
}

// file walks

/* One cold walk of a file. Each segment of the text ends before an include,
   and `line` and `pos` locate the current segment's
   first token. `deferred` marks an entry collected without its declaration
   defaults. A module's walk reads its spliced text. */
static typedef struct FileWalk {
  Compiler c, String path, text, dir, ModuleSource module, Map globs, visited;
  Array parts, Map definitions, dependencies, statics, hashes;
  int unit, linkage, line, pos, deferred;
} FileWalk;

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
  $let(c.collection_native, 0)
  $let(c.declaration_effects, NULL) $let(c.kw_aliases, {})
  $let(c.layout, tokenizer.layout) {
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
        %(meta-hashes $provider ${w.hashes});
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

static void _split(FileWalk &w, Token first) {
  Array arms = $auto([]);
  for (Token token = first; token.type != <eof>; token++) {
    if (token.type != <preproc> || !_starts_line(first, token)) continue;
    if (!_track_arms(arms, token.text)) _directive(w, token, _hidden(arms));
  }
  _flush(w, w.text[w.pos:]);
}

/* An include ends the segment unless its conditional arm is never taken. */
static void _directive(FileWalk &w, Token token, int hidden) {
  int angle = 0;
  String target =
    hidden ? NULL : Compiler.preproc_include_target(token.text, angle);
  if (!target) return;
  _flush(w, w.text[w.pos:token.pos]);
  _include_file(w, target, angle);
  Token next = token + 1;
  w.line = next.line;
  w.pos = next.pos;
}

/* A directive's `#` follows only whitespace and comments on its line. */
static int _starts_line(Token first, Token token) {
  while (token-- > first) {
    if (token.type != <space> && token.type != <comment>) return 0;
    if ("\n" in token.text) return 1;
  }
  return 1;
}

/* Tracks the open conditional groups of a walk, one hidden-arm state each,
   and reports whether `text` is a conditional directive. */
static int _track_arms(Array arms, String text) {
  Symbol kind = Compiler.preproc_conditional_kind(text);
  if (!kind) return 0;
  if (kind == <open>) arms.push(Compiler.preproc_open_state(text));
  else if (kind == <branch> && arms.len())
    arms[-1] = Compiler.preproc_branch_state(arms[-1]);
  else if (kind == <close> && arms.len()) arms.take_last();
  return 1;
}

static int _hidden(Array arms) {
  foreach (int state, arms) if (state == 2) return 1;
  return 0;
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
   are recorded at this segment's source position. Macro, Lisp, and keyword
   state then returns to the enclosing compiler for the next segment. */
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
  if (!w.unit || !_package_owns(w.c, w.path)) shadow.package = NULL;
  shadow.filename = w.path;
  shadow.load_source =
    w.c.load_source && w.path == Path.absolute(w.c.filename);
  // Every segment hashes its provider, including its private helpers.
  shadow.meta_hashes = w.hashes;
  shadow.layout = w.c.layout;
  shadow.source_private = 0;
  shadow.signature_only = w.c.signature_only;
  shadow.interface_provider = w.c.interface_provider;
  shadow.open_linkage = w.linkage;
  shadow.take_unit_state(w.c);
  shadow.tokenize(segment);
  shadow.text = w.text;
  if (w.module) shadow.line_markers = w.module.markers;
  if (w.c.source_facts)
    w.c.source_texts[Path.absolute(w.path)] =
      w.module ? w.module.own : w.text;
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
static int _package_owns(Compiler c, String path) {
  if (!c.package) return 0;
  Var root = c.package_roots[c.package];
  return root is not void &&
    path.startswith(%"${_canonical_path(root)}/");
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

/* Type rows keep their complete family: the tag, its fields and field
   order, or a typedef and its ordinary-name row. A public declaration can
   require an otherwise static family, including through an alias chain. */
static List _type_family(List key) {
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
static void _needed_types(List syntax, Map rows, Map needed) {
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
    foreach (Var part, item) pending.push(part);
  }
}

static void _select_public(FileWalk &w) {
  if (!w.unit) return;
  Map rows = {}, needed = {}, selected = {};
  foreach (Var part, w.parts) if (part is <map>) rows.merge(part);
  foreach (Var (key, value), rows) {
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
    foreach (Var (key, value), rows) {
      List family = _row_type_family(rows, w.statics, key, value);
      if (!family || !(family in needed) || key in selected) continue;
      selected[key] = 1;
      if (value is <list>) _needed_types(value, rows, needed);
      changed = 1;
    }
  } while (changed);
  foreach (Var part, w.parts) {
    if (part is not <map>) continue;
    Array dropped = $auto([]);
    foreach (Var key, part.map().keys())
      if (!(key in selected)) dropped.push(key);
    foreach (Var key, dropped) part.map().del(key);
  }
}

/* A `static` function belongs to the file that defines it, so its
   declaration row never crosses an include.
   The published marker names the defining file, which lets an including unit
   report a reference to the name instead of emitting a prototype that no
   object defines. The file is spelled home-portably, as interfaces spell
   paths. Only `.x` units publish markers; a C header's static inline
   functions belong to every file that includes it. */
static void _publish_unit_statics(Map statics, Map overlay, String path) {
  List owner = %(${Compiler.portable_path(path)});
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
static void _include_file(FileWalk &w, String target, int angle) {
  int covered = 0;
  String path = _resolve_include(
    w.c.sources, w.c.include_dirs, w.dir, target, angle, covered, w);
  if (!path || (covered && !Path.is_x2c_source(path))) return;
  String canonical = _canonical_path(path);
  w.c.add_translation_dependency(canonical);
  if (!(canonical in w.visited)) {
    w.visited[canonical] = 1;
    List entry = _collection_entry(w.c, canonical);
    if (!entry) entry = _walk_cold(w.c, target, canonical, w.globs, w.visited);
    _replay_cached(
      w.c, entry, canonical, w.globs, w.visited, NULL);
  }
  else if (w.visited[canonical] is <array>)
    _replay_included(w.c, w.globs, canonical, {}, NULL, w.visited);
  _cache_dependency(
    w.dependencies, canonical, _walked_hash(w.c, target, canonical));
  w.parts.push(canonical);
}

/* Preserve absent candidates and alias identity, not directory timestamps.
   Canonical selected files already carry their ordinary content hashes. */
static void _include_search_dependency(
  FileWalk &w, String candidate) {
  if (!candidate.startswith("/")) candidate = %"cwd:$candidate";
  if (!candidate.startswith("cwd:") && w.c.sources.exists(candidate) &&
      candidate == _canonical_path(candidate)) return;
  String hash = _include_search_hash(w.c, candidate);
  _cache_dependency(w.dependencies, candidate, hash);
  w.c.deps.merge_translation_dependency(candidate, hash);
}

static String _include_search_hash(Compiler c, String path) {
  if (path.startswith("cwd:")) path = path[4:];
  return c.sources.exists(path) ?
    %"search:${Compiler.portable_path(Path.absolute(path))}" : "search:absent";
}

/* A file still being walked, as in an include cycle, has no entry yet. */
static String _walked_hash(
  Compiler c, String target, String canonical) {
  Var walked = _process_cache()[canonical];
  if (walked is void)
    return _content_hash(_include_text(c, target, canonical));
  return walked.list().cadr();
}

/* Read an include's text, reporting an unreadable target as a driver error. */
static String _include_text(Compiler c, String target, String path) {
  String text = NULL;
  if (c.read_source(path, text)) return text;
  $report.driver.include_read(c, target, path);
}

/** Selects a source file's own package, as its standalone translation does.
    A cold provider does not register an import in its including unit. */
void Compiler.configure_package(Compiler c, List roots, String filename) {
  String source = Path.absolute(filename);
  String package = Compiler.package_directory(roots, source);
  if (!package || !Compiler.is_package_source(package, source)) return;
  String name = Path.basename(package);
  c.package = name;
  if (!(name in c.package_roots)) c.package_roots = c.package_roots.copy();
  c.package_roots[name] = package;
}

/* Walk one included file cold and return its entry. The walk reads the
   includer's names through copies, so its private rows and includes stay
   there. It runs in a compiler of its own, with the macro, import, keyword,
   and Lisp state the file's own translation starts with. The includer
   replays the selected public definitions as any later unit would. */
static List _walk_cold(
  Compiler c, String target, String canonical, Map globs, Map visited) {
  String text = _include_text(c, target, canonical);
  Compiler file = Compiler.new_shared(c);
  defer c.close_child(file);
  file.interface_provider = 1;
  file.configure_package(c.package_source_dirs, canonical);
  file.signature_only = c.signature_only;
  file.filename = c.filename;
  // Every file the shared session preloads defines its Lisp there.
  if (Compiler.library_filling()) {
    file.macro_lisp = c.macro_lisp;
    file.borrowed_lisp = 1;
  }
  else file.evaluated_effects = {};
  /* A fresh file installs its own includes in its own macro state. Only
     active walks cross into that state, to preserve a cycle's prefix. */
  Map own_visited = {};
  foreach (Var (path, state), visited)
    if (state is <array>) own_visited[path] = state;
  _walk_apart(file, canonical, text, globs.copy(), own_visited);
  c.merge_translation_dependencies(file.deps);
  c.declaration_produced |= file.declaration_produced;
  return _process_cache()[canonical];
}

/* A cold included file has its own generated spellings. Binding identities
   remain unique across the unit and its pending inline-body parses. */
static void _walk_apart(
  Compiler c, String path, String text, Map globs, Map visited) {
  ModuleSource module = c.module_source(path, text);
  $let(c.names.counters, {})
    _walk_file(c, path, text, module, Path.dirname(path), globs, visited);
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
  Array dirs = $auto(_include_dirs(
    extra_dirs, angle ? NULL : includer_dir, !walk));
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
  foreach (Var dir, extra_dirs)
    if (dir is <string>) dirs.push(canonical ? _canonical_path(dir) : dir);
  return dirs;
}

/** The file the include of `target` from `includer_dir` names, searched as
    collection searches `dirs`, or NULL. */
String SourceView.resolve_include(
  SourceView s, List dirs, String includer_dir, String target, int angle) {
  int covered = 0;
  return _resolve_include(
    s, dirs, includer_dir, target, angle, covered, NULL);
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
  foreach (Var part, entry.car())
    match (%($part)) {
      case %(?(Map rows)):
        foreach (Var (key, value), rows) {
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
  foreach (Var part, entry.list().car())
    if (part is <string>) _add_function_declarations(c, part, available);
}

static void _add_function_declarations(
  Compiler c, String path, Map available) {
  if (path == _canonical_path(c.filename)) return;
  Var entry = _process_cache()[path];
  if (entry is not <list>) return;
  foreach (String name, _declared_functions(entry))
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
    foreach (Var part, entry.car()) {
      if (part is not <map>) continue;
      foreach (Var (key, value), part.map())
        match (key) case %(?(String name))
          if (value is <list> && value.list().type().is_function()):
            names.push(name);
    }
    declared_functions[entry] = names;
    return names;
  }
}

/** Reports whether a linked provider and the files it read are unchanged.
    The linked inventory retains the ordinary collector's dependency proof. */
int Compiler.linked_meta_provider_current(Compiler c, String path) {
  String canonical = _canonical_path(path);
  _interface_lisp();
  Var current;
  if (linked_providers.try_get(canonical, current)) return current;
  Map seen = {};
  int valid = _linked_provider_current(c, canonical, seen);
  if (valid)
    foreach (String dependency, seen.keys()) {
      _retain(dependency);
      linked_providers[dependency] = 1;
    }
  else {
    _retain(canonical);
    linked_providers[canonical] = 0;
  }
  return valid;
}

static int _linked_provider_current(
  Compiler c, String path, Map seen) {
  Var current;
  if (linked_providers.try_get(path, current)) return current;
  if (path in seen) return 1;
  seen[path] = 1;
  List source =
    Compiler.linked_meta_provider_source(Compiler.portable_path(path));
  match (source)
    case %(source ?hash ?(List dependencies) *): {
      if (!_hash_matches(c, path, hash)) return 0;
      Map found = _read_dependencies(c, dependencies);
      if (found == NULL) return 0;
      // Member content was hashed above; only included units own proofs.
      foreach (Var (dependency, expected), found)
        if (Path.is_x2c_source(dependency) && expected is <string> &&
            !String.startswith(expected, "search:") &&
            Compiler.linked_meta_provider_source(
              Compiler.portable_path(dependency)) &&
            !_linked_provider_current(c, dependency, seen)) return 0;
      return 1;
    }
  return 0;
}

/** Reports whether a provider's linked definition hashes still match.
    Changes outside definitions do not require a project helper. */
int Compiler.linked_meta_definitions_current(Compiler c, String path) {
  if (c.linked_meta_provider_current(path)) return 1;
  String canonical = _canonical_path(path);
  String provider = Compiler.portable_path(canonical);
  List source = Compiler.linked_meta_provider_source(provider);
  match (source) case %(source ?hash *):
    if (_hash_matches(c, canonical, hash)) return 1;
  match (source) case %(source ? ? ?(String definitions)): {
    List entry = _meta_provider_entry(c, canonical);
    if (!entry) return 0;
    foreach (Var part, entry.car()) {
      if (part is not <map>) continue;
      Var value;
      if (!part.map().try_get(
        %("source-node" (meta-hashes $provider 0)), value)) continue;
      Map hashes = value.list().caddr();
      return _content_hash(_stored_meta_hashes(hashes)) == definitions;
    }
  }
  return 0;
}

/* Metadata lookahead reads declarations and hashes without source effects. */
static List _meta_provider_entry(Compiler c, String canonical) {
  List entry = _entry(c, canonical);
  if (!entry) {
    DiagnosticsHold hold = c.diagnostics.hold();
    $let(c.meta_build, 1) $let(c.signature_only, 1)
    $let(c.recovery_depth, c.recovery_depth + 1) {
      try entry = _walk_cold(c, canonical, canonical, {}, {});
      catch %(malformed *): entry = NULL;
    }
    c.diagnostics.release(hold, 0);
  }
  return entry;
}

/** Completes a linked function's own source hashes before a shallow call.
    A lookahead entry never replaces the file's ordinary contribution. */
void Compiler.complete_meta_hashes(Compiler c) {
  List entry = _meta_provider_entry(c, _canonical_path(c.filename));
  if (entry)
    foreach (Var part, entry.car()) {
      if (part is not <map>) continue;
      foreach (Var value, part.map())
        match (value) case %(meta-hashes ? ?(Map hashes)):
          c.meta_hashes.merge(hashes);
    }
  Compiler.forget_provisional_entries();
}

/** Returns the shared function hashes of an advertised meta provider. */
Map Compiler.meta_provider_hashes(Compiler c, String provider) =>
  c.sym.get_exact(%("source-node" (meta-hashes $provider 0))).caddr();

/** Retains source proofs and one definition hash per linked provider. */
void Compiler.add_linked_meta_provider_hashes(Compiler c, Map rows) {
  foreach (String path, c.deps.keys()) {
    if (!Path.is_x2c_source(path)) continue;
    List entry = _entry(c, _canonical_path(path));
    if (!entry) continue;
    String provider = Compiler.portable_path(_canonical_path(path));
    List proof = NULL;
    Map hashes = NULL;
    foreach (Var part, entry.car()) {
      if (part is not <map>) continue;
      Var value;
      if (part.map().try_get(
        %("source-node" (provider-source $provider 0)), value))
        proof = value;
      if (part.map().try_get(
        %("source-node" (meta-hashes $provider 0)), value))
        hashes = value.list().caddr();
    }
    foreach (String name, hashes.keys()) {
      if (!(name in c.project_meta) && !(name in c.meta_calls)) continue;
      proof = proof.append(
        %(${_content_hash(_stored_meta_hashes(hashes))}));
      break;
    }
    rows[provider] = proof;
  }
}

/** Selects helper C spellings for public definitions owned by `path`.
    Bindings, rather than source tokens, keep unrelated private names and
    fields unchanged. Native supplier declarations retain their C names. */
void Compiler.name_meta_provider_bindings(
  Compiler c, String path, int index) {
  List entry = _entry(c, _canonical_path(path));
  if (!entry) return;
  foreach (String name, entry.caddr()) _name_meta_provider(c, name, index);
  foreach (Var part, entry.car()) {
    if (part is not <map>) continue;
    foreach (Var value, part.map())
      match (value) case %(native-object ?(String name)):
        _name_meta_provider(c, name, index);
  }
}

/** Returns this source's native definitions with their canonical declarations
    and the public type rows needed to check other units' declarations. */
List Compiler.loaded_provider(Compiler c) {
  List entry = _entry(c, _canonical_path(c.filename));
  Array names = [];
  foreach (String name, entry.caddr())
    if (name != "main" || c.load_source) names.push(name);
  foreach (Var part, entry.car())
    if (part is <map>)
      foreach (Var value, part.map())
        match (value) case %(native-object ?(String name)):
          names.push(name);
  List owned = names.list_free();
  Map symbols = c.callable_symbols(owned), declarations = {};
  foreach (String name, owned)
    declarations[name] = _loaded_declaration(c, symbols[%($name)]);
  return %($declarations $symbols);
}

/** Returns the native calling type of a loaded function. Array parameters
    decay to pointers, and a parameter's outer qualifiers affect only its
    local copy. Keep the declared type for inspection and reload checks. */
Type Compiler.loaded_call_type(Compiler c, Type type) {
  List parameters = NULL;
  Type result = NULL;
  type.function_parts(parameters, result);
  Array adjusted = [];
  foreach (Type parameter, parameters) {
    Type shape = c.sym.normalize_declared_type(parameter);
    if (shape.is_array()) parameter = shape.dereference().reference();
    while (parameter.car() is <symbol> &&
           parameter.car().symbol().is_type_qualifier())
      parameter = parameter.cdr();
    adjusted.push(parameter);
  }
  return %((func ${adjusted.list_free()}) @result);
}

static Type _loaded_declaration(Compiler c, Type type) {
  type = c.sym.normalize_declared_type(type);
  if (!type.is_function()) return type;
  List parameters = NULL;
  Type result = NULL;
  type.function_parts(parameters, result);
  Array declared = [];
  foreach (Type parameter, parameters)
    declared.push(c.sym.normalize_declared_type(parameter));
  List args = parameters ? declared.list_free() : %((void));
  return c.loaded_call_type(
    %((func $args) @{c.sym.normalize_declared_type(result)}));
}

/** Names declared bindings through one loaded provider. Its own source
    declarations remain authoritative; private bindings never link out. */
void Compiler.name_loaded_provider(
  Compiler c, String path, int index, List provider) {
  (Map declarations, Map symbols) = provider;
  Map visible = $auto(c.sym.unit_symbols());
  foreach (Var (name, expected), declarations) {
    if (%($name) in c.sym.file_statics() ||
        %(function $name) in c.sym.file_statics()) continue;
    Type type = NULL;
    List binding = c.sym.resolve_global(%($name), type);
    if (!binding) continue;
    if (!_loaded_types_equal(_loaded_declaration(c, type), expected) ||
        !_loaded_type_rows(type, visible, symbols))
      $report.type.loaded_declaration(c, name, path);
    _name_meta_provider(c, name, index);
    // C headers keep their source spellings; declare the linked spelling too.
    type = type.declared();
    c.add_early(c.rebuild_statement($!{ extern $type $binding; }).cadr());
  }
}

static int _loaded_types_equal(Type declared, Type defined) {
  if (declared.equal(defined)) return 1;
  return declared.is_array() && defined.is_array() &&
    declared.car().list().len() == 1 && declared.cdr().equal(defined.cdr());
}

/* Compare complete type families actually named by the declaration. A
   forward declaration can remain incomplete in the calling source. */
static int _loaded_type_rows(Type type, Map visible, Map provider) {
  Map needed = $auto({}), checked = $auto({});
  _needed_types(type, visible, needed);
  int changed = 1;
  while (changed) {
    changed = 0;
    foreach (Var (key, value), visible) {
      List family = _type_family(key);
      if (!family || !(family in needed) || key in checked) continue;
      Var expected;
      if (provider.try_get(key, expected) && !value.equal(expected)) return 0;
      checked[key] = 1;
      if (value is <list>) _needed_types(value, visible, needed);
      changed = 1;
    }
  }
  return 1;
}

static void _name_meta_provider(
  Compiler c, String name, int index) {
  if (%($name) in c.sym.file_statics()) return;
  if (name in c.native_meta && c.bind_native_meta(name)) return;
  List binding = c.sym.lookup(%($name), NULL);
  if (binding)
    c.set_fact(%(emitted $binding), %"_x2c_gensym_meta_group_${index}_$name");
}

/** Reports whether this unit's selected interface publishes `name`. */
int Compiler.publishes_typedef(Compiler c, String name) {
  return c.publishes_type_family(%(typedef $name));
}

/** Reports whether this unit's interface publishes the type `family`. */
int Compiler.publishes_type_family(Compiler c, List family) {
  List entry = _entry(c, _canonical_path(c.filename));
  if (!entry) return 0;
  foreach (Var part, entry.car())
    if (part is <map> && family in part.map()) return 1;
  return 0;
}

static void _add_typedef_names(
  Compiler c, Array names, String path, Map seen) {
  if (path in seen || _in_runtime(path)) return;
  seen[path] = 1;
  List entry = _entry(c, path);
  if (entry)
    foreach (Var part, entry.car())
      match (%($part)) {
        case %(?(Map rows)):
          foreach (Var key, rows.keys())
            match (%($key)) case %((typedef ?(String name))):
              names.push(name);
        case %(?(String include)):
          _add_typedef_names(c, names, include, seen);
      }
}

/* Unresolvable paths retain the caller's spelling. This is
   `Compiler.canonical_path` without a source view: an unsaved file keeps
   the spelling the include search built, which keys its process-cache
   entry, and `SourceView.resolve_include` searches with no Compiler. */
static String _canonical_path(String path) {
  String real = Path.real(path);
  return real ? real : path;
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
static void _add_defaults(FileWalk &w) {
  if (w.c.signature_only || !_produces(w)) return;
  w.deferred = Compiler.library_filling();
  if (w.deferred) return;
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
  foreach (Var key, w.statics.keys())
    if (key is <list> && _type_family(key)) private_types = 1;
  if (!private_types) return;
  int exposed = 0;
  foreach (Var part, w.parts) if (part is <map>)
    foreach (Var key, part.map().keys())
      match (key) case %("function-inline" ?): exposed = 1;
  if (!exposed) return;
  if (Compiler.library_filling() || w.c.meta_build) {
    w.deferred = 1;
    return;
  }
  Map own = {};
  foreach (Var part, w.parts) if (part is <map>) own.merge(part);
  w.c.public_bodies = 1;
  w.c.pending_inline_bodies.push(
    %(${w.c} ${w.path} ${w.text} ${w.globs} $own
      ${w.statics} ${w.hashes} @{w.module ? %(${w.module.markers}) : NULL}));
}

/* Each provider binds its header bodies in its own original session.
   Included signatures come from the completed graph; effects still install
   at the provider's ordinary include positions. Remove the work before
   replay, because a cold dependency can complete more pending providers. */
static void _bind_pending_inline_bodies(
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
    Map additions = body.inline_type_dependencies(ast);
    _publish_inline_dependencies(body, path, own, statics, additions);
    foreach (Var part, _entry(body, path).car())
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
  foreach (Var part, entry.car())
    if (part is <map>)
      foreach (Var key, part.map().keys())
        match (key) case %("unit-static" ?): globs.del(key);
}

static int _produces(FileWalk &w) {
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
      %(source $hash ${_stored_dependencies(w.dependencies)});
    w.parts.push(metadata);
  }
  List parts = w.parts.list_free();
  _retain(w.path);
  _retain_rows(parts);
  foreach (Var (name, hash), w.hashes) {
    _retain(name);
    _retain(hash);
  }
  List definitions = _sorted_names(w.definitions);
  List roots = _interface_include_dirs(w.c, w.path);
  List entry = %($parts $hash $definitions ${w.dependencies} $roots);
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

static int _declares_adoption(List parts) {
  foreach (Var part, parts)
    if (part is <map>)
      foreach (Var value, part.map())
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
static void _record_cold_conformances(
  Compiler c, Map globs, Map visited, String unit) {
  ColdConformances cold = {.c = c};
  defer if (cold.prelude_session) c.close_child(cold.prelude_session);
  while (cold_providers) {
    Map pending = cold_providers;
    cold_providers = NULL;
    foreach (Var path, pending.keys()) {
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
  foreach (String source, Compiler.prelude_sources())
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
  foreach (Var name, entry.caddr()) into.definitions[name] = 1;
  foreach (Var part, entry.car()) {
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
  foreach (Var (key, value), view.symbols) {
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

/** Records the actual type dependencies of typed public inline bodies. */
Map Compiler.inline_type_dependencies(Compiler c, List ast) {
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
              foreach (List binding, bindings) {
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
        foreach (Var type, types.keys()) ordered.push(type);
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
  Map additions = c.inline_type_dependencies(ast);
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
  foreach (Var value, additions) _needed_types(value, all, needed);
  int changed;
  do {
    changed = 0;
    foreach (Var (key, value), all) {
      List family = _row_type_family(all, statics, key, value);
      if (!family || !(family in needed) || key in selected) continue;
      selected[key] = 1;
      additions[key] = value;
      if (value is <list>) _needed_types(value, all, needed);
      changed = 1;
    }
  } while (changed);
  Map published = {};
  foreach (Var part, entry.car())
    if (part is <map>)
      foreach (Var key, part.map().keys()) published[key] = part;
  Array dropped = $auto([]);
  foreach (Var key, additions.keys()) {
    Var owner;
    if (published.try_get(key, owner) &&
        owner.map()[key] == additions[key]) dropped.push(key);
  }
  foreach (Var key, dropped) additions.del(key);
  _cache_dependencies(entry[3], c.deps);
  if (!additions.len()) return;
  Map retained = _cache_copy(additions);
  _retain_rows(%($retained));
  Array replaced = $auto([]);
  foreach (Var (key, value), retained) {
    Var owner;
    if (!published.try_get(key, owner)) continue;
    owner.map()[key] = value;
    replaced.push(key);
  }
  foreach (Var key, replaced) retained.del(key);
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
  foreach (Var part, cached.list().car())
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
  foreach (Var part, cached.list().car()) {
    if (part is not <map>) continue;
    contribution = part;
    Array stale = $auto([]);
    foreach (Var (key, value), contribution)
      match (value) case %(conformance *): stale.push(key);
    foreach (Var key, stale) contribution.del(key);
  }
  if (contribution == NULL) return;
  foreach (Var (key, value), rows) {
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
  foreach (Var part, cached.list().car())
    if (part is <map>)
      foreach (Var value, part.map())
        match (value) {
          case %(adopt *): adoptions.push(value);
          case %(package-import *): return NULL;
        }
  return adoptions;
}

// replay

/* Replay declaration maps and includes in their recorded source order.
   visited counts each included file's declarations, dependencies, and
   function definitions once per translation unit. In-memory and interface
   entries have the same shape and take this same path. Source traversal
   keeps its processed prefix as a cold walk does. An effects array marks
   completed-provider replay for full parsing. */
static void _replay_cached(
  Compiler c, List entry, String path, Map globs, Map visited,
  Array effects) {
  Array prefix = effects != NULL ? NULL : [];
  if (prefix != NULL) visited[path] = prefix;
  foreach (Var name, entry.caddr()) c.fn_defs[name] = 1;
  /* Parsing this file read these macro and Lisp files. They are
     prerequisites of every unit that reaches it, not only of the one that
     parsed it. */
  c.merge_translation_dependencies(entry[3]);
  foreach (Var part, entry.car()) {
    if (part is <map>) {
      _merge_rows(c, globs, part);
      c.replay_package_imports(globs, part, effects);
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

// package imports

/* One package's public surface while it is gathered: the package's name
   and root, the rows merged so far, the files already visited, and the
   token that locates errors. */
static typedef struct Surface {
  Compiler c, String name, root, Map merged, visited, Token token;
  Array exports;
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
  $report.driver.package_unknown(c, token, name);
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
    $report.driver.package_read(c, token, package, entry);
  _walk_apart(package, entry, text, globs, visited);
}

/* Replay each package include once and record its dependencies. */
static void _gather_surface(Surface &s, String path, List entry) {
  s.c.merge_translation_dependencies(entry[3]);
  foreach (Var part, entry.car())
    match (%($part)) {
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
  String prefix = %"${s.name}__";
  int keeps = _keeps_spellings(path);
  int foreign = !path.startswith(%"${s.root}/");
  _take_exports(s, rows);
  foreach (Var (key, value), rows) {
    if (key is not <list> || key.is_nil()) continue;
    String spelling = _package_key_spelling(key);
    if (_package_protocol_row(key, value)) _take(s, rows, key, value);
    else if (spelling && (keeps || spelling.startswith(prefix)))
      _take(s, rows, key, value);
    else if (spelling && foreign) _reject(s, path, spelling);
  }
}

/* Compile-time definitions follow the package's ordinary include walk. */
static void _take_exports(Surface &s, Map rows) {
  Array found = $auto([]);
  foreach (Var (key, value), rows)
    match (%($key $value))
      case %(("source-node" (? ? ?position))
             (!set ?effect ((!or compile-time project-meta) *))):
        found.push(%($position $effect));
  found.sort();
  foreach (List entry, found) s.exports.push(entry.cadr());
}

static void _take(Surface &s, Map rows, List key, Var value) {
  s.merged[key] = value;
  s.c.copy_source_declaration(s.merged, rows, key);
}

static void _reject(Surface &s, String path, String spelling) {
  String name = s.name, unit = path.split("/").last();
  String fix = %"directly, or move it into '$name/src'";
  $report.driver.package_prefix(s.c, s.token, name, spelling, unit, fix);
}

/* The merged rows enter the importing unit's symbols. */
static void _install(Surface &s) {
  foreach (Var (key, value), s.merged) {
    s.c.sym.set(key, value);
    s.c.copy_source_declaration(s.c.sym.current_symbols(), s.merged, key);
  }
}

/* A C header or a runtime module crosses with its own spellings. */
static int _keeps_spellings(String path) =>
  !Path.is_x2c_source(path) || _in_runtime(path);

static int _in_runtime(String path) =>
  path.startswith(%"${_canonical_lib()}/") ||
  path.startswith(%"${_canonical_include()}/");

/* A declaration key is a plain name, or a typedef or aggregate name that a
   member row may extend; the tag covers the whole family, so a member of a
   prefixed aggregate crosses with it. Source-node and helper rows carry no C
   spelling of their own. */
static String _package_key_spelling(List key) {
  match (key) case %("function-inline" ?(String name)): return name;
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

/** Replays package imports and public compile-time definitions in source
    order. The shadow borrows the unit's macro state and package registries.
    The full parse collects effects for the include line and leaves the
    unit's own definitions at their source sites.
*/
void Compiler.replay_package_imports(
  Compiler c, Map globs, Map rows, Array exports) {
  Array imports = NULL;
  defer if (imports) imports.free();
  foreach (Var (key, value), rows)
    match (key)
      case %("source-node" (? ?path ?position)): {
        if (value is not <list> || !value.list() ||
            !(value.list().car() in
              %(package-import compile-time project-meta))) continue;
        if (exports == NULL || !_imported_here(c, path)) {
          if (!imports) imports = [];
          imports.push(%($path $position $value));
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
  foreach (List entry, imports)
    match (entry) {
      case %(?(String path) ?
             (package-import ?(String name) ?(String alias) ?members)):
        _import_package(shadow, path, name, alias, members, exports);
      case %(? ? (!set ?effect ((!or compile-time project-meta) *))):
        if (exports != NULL) exports.push(effect);
        else shadow.install_compile_time_effects(%($effect));
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
  foreach (List member, members)
    c.register_package_member(name, member.car(), member.cadr(), NULL, NULL);
  if (effects != NULL)
    foreach (Var effect, c.package_effects[name]) effects.push(effect);
  else c.install_compile_time_effects(c.package_effects[name]);
}

/** Prepares included compile-time effects after full parsing resets macros.
    The ordered cache walk counts each file once and groups effects by the
    canonical path of the unit's direct include. The parser installs those
    effects when it reaches that include.
*/
Map Compiler.included_compile_time_effects(Compiler c, Map globs) {
  Map visited = {}, delivered = {};
  if (c.prelude) {
    Array effects = [];
    foreach (String source, Compiler.prelude_sources()) {
      String path = _canonical_path(%"${x2c_get_root()}/$source");
      _replay_included(c, globs, path, visited, effects, NULL);
    }
    $let(c.builtin_defs, 1)
      c.install_compile_time_effects(effects.list_free());
  }
  String unit = _canonical_path(c.filename);
  visited[unit] = 1;
  List entry = _entry(c, unit);
  if (!entry) return delivered;
  foreach (Var part, entry.car()) {
    Array exports = [];
    if (part is <map>) c.replay_package_imports(globs, part, exports);
    else if (part is <string>) {
      _replay_included(c, globs, part, visited, exports, NULL);
      if (exports.len()) delivered[part] = exports.list_free();
    }
  }
  return delivered;
}

/* Active walks supply their public recorded prefix during an include cycle. */
static void _replay_included(
  Compiler c, Map globs, String path, Map visited, Array exports,
  Map active) {
  if (path in visited) return;
  visited[path] = 1;
  Var prefix = active ? active[path] : void;
  List entry = prefix is <array> ? NULL : _entry(c, path);
  if (!entry && prefix is not <array>) return;
  List parts = prefix is <array> ? prefix.array().list() : entry.car();
  foreach (Var part, parts) {
    if (part is <map>) c.replay_package_imports(globs, part, exports);
    else if (part is <string>)
      _replay_included(c, globs, part, visited, exports, active);
  }
}

/** Installs the definitions of each include among the directives before
    the cursor. */
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
    c.install_compile_time_effects(exports);
  }
}

// unit interfaces

/* A `.xi` interface is one unit's cache entry written beside its generated
   C. It records the identity of the compiler that wrote it, because a
   different compiler may collect different rows from the same source.
   Missing, stale, foreign, or malformed interfaces are cache misses; the
   caller walks the file cold and installs that result in the process cache.
   Paths inside an interface use `Compiler.portable_path` spellings. */

static String interface_out_dir = NULL, interface_mirror = NULL;

/* Interfaces name the same sources many times, so a process hashes each
   source once. */
static Map source_hashes = NULL, linked_providers = NULL;
static Lisp interface_reader = NULL;

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
  interface_mirror = cold ? NULL : stage ? stage : x2c_get_root();
}

/* Find and validate the interface of one canonical source path: the
   record linked into the compiler for a prelude component, else its `.xi`.
   A source under inspection through a SourceView, or a cold process, reads
   neither. */
static List _interface_read(Compiler c, String canonical) {
  if (c.source_facts || !interface_mirror) return NULL;
  List record = _linked_record(canonical);
  if (record) {
    List entry = _stored_entry(c, canonical, record);
    if (entry) return entry;
  }
  foreach (String path, _interface_candidates(canonical)) {
    List entry = _interface_load(c, canonical, path);
    if (entry) return entry;
  }
  return NULL;
}

/* Candidate interface paths for one canonical source path: the output
   directory by stem, its sibling that mirrors a home file's directory, the
   home mirror, and a package's `builds/` beside or above the source. */
static List _interface_candidates(String canonical) {
  String stem = Path.stem(canonical);
  String relative = Compiler.portable_path(canonical);
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
   ownership and the same ordered parts representation as a cold walk. */
static List _interface_load(
  Compiler c, String canonical, String path) {
  String identity = Compiler.identity();
  match (_interface_record(path))
    case %(interface 6 ?(String compiler) *stored):
      if (identity && compiler == identity)
        return _stored_entry(c, canonical, stored);
  return NULL;
}

/* The entry of a stored record whose source, hash, and include roots still
   match `canonical`, or NULL. */
static List _stored_entry(Compiler c, String canonical, List stored) {
  match (stored)
    case %(?(String owner) ?(String hash) ?(List parts) ?(List definitions)
           ?(List dependencies) ?(List include_dirs)):
      if (Compiler.absolute_home_path(owner) == canonical &&
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
  _interface_lisp();  // a reader session, for text the plain read leaves
  unsigned cursor = 0;
  Var record = void;
  int read = 0;
  try read = datum_read_plain(source, cursor, record);
  catch %((!or incomplete malformed) *): return NULL;
  if (!read || record is not <list>) return NULL;
  return record;
}

static Lisp _interface_lisp(void) {
  if (interface_reader) return interface_reader;
  _process_cache();
  $scope(&process_cache_scope) {
    interface_reader = Lisp.kernel();
    source_hashes = {};
    linked_providers = {};
    Scope.shutdown_hook(_interface_shutdown);
  }
  return interface_reader;
}

static void _interface_shutdown(void) {
  Lisp.destroy(interface_reader);
  interface_reader = NULL;
  source_hashes = NULL;
  linked_providers = NULL;
}

static int _hash_matches(Compiler c, String path, Var expected) {
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
  foreach (Var definition, definitions)
    if (definition is not <string>) return NULL;
  List entry = %(
    ${parts.list_free()} $hash $definitions $dependencies $include_dirs);
  _retain(canonical);
  _require_retained(entry.try_own());
  _process_cache()[canonical] = entry;
  return entry;
}

/* A stored part is an include path or a list of rows. */
static int _read_parts(Array parts, List stored) {
  foreach (Var part, stored) {
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
  foreach (Var row, stored) {
    if (row is not <list> || row.list().len() != 2) return NULL;
    List pair = row;
    _require_retained(pair.try_own());
    Var (key, value) = pair;
    if (value is <list>) match (value)
      case %(meta-hashes ?provider ?(List stored)): {
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
static Map _read_dependencies(Compiler c, List stored) {
  Map dependencies = _cache_map();
  foreach (Var dependency, stored) {
    if (dependency is not <list>) return NULL;
    match (dependency.list())
      case %(?(String name) ?hash): {
        String path = hash is <string> && String.startswith(hash, "search:") ?
          (name.startswith("cwd:") ? name : Compiler.absolute_home_path(name)) :
          _canonical_path(Compiler.absolute_home_path(name));
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
String Compiler.prelude_interface(void) {
  String identity = Compiler.identity();
  if (!identity) return NULL;
  String runtime = _canonical_path(%"${x2c_get_root()}/lib/x2c.x");
  String header = %"(interface 6 \"$identity\" ";
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
String Compiler.interface_text(Compiler c) {
  if (!Compiler.identity()) return NULL;
  String canonical = _canonical_path(c.filename);
  Var cached = _process_cache()[canonical];
  if (cached is void) return NULL;
  Buffer out = $auto(Buffer.new(0));
  if (_write_interface_entry(out, canonical, cached)) return out;
  $report.emit.interface_write(c);
}

static int _write_interface_entry(
  Buffer out, String canonical, List entry) {
  List record = %(
    interface 6 ${Compiler.identity()} @{_stored_record(canonical, entry)});
  /* An interface is plain data, which a loader never evaluates. */
  if (!datum_write(out, record, 0)) return 0;
  out.write_char('\n');
  return 1;
}

/* An entry as an interface stores it after the compiler identity. */
static List _stored_record(String canonical, List entry) {
  (List cached_parts, Var hash, List definitions, Map dependencies,
   List include_dirs) = entry;
  Map identities = {}, Array parts = [];
  foreach (Var part, cached_parts) parts.push(_stored_part(part, identities));
  return %(
    ${Compiler.portable_path(canonical)} $hash ${parts.list_free()}
    $definitions ${_stored_dependencies(dependencies)} $include_dirs);
}

/* Search roots and the file's package mode must match before replay. */
static List _interface_include_dirs(
  Compiler c, String canonical) {
  Array dirs = [];
  foreach (String dir, c.include_dirs) {
    String portable = Compiler.portable_path(dir);
    dirs.push(
      dir == x2c_get_root() ? %(home "") :
      portable != dir ? %(home $portable) :
      dir.startswith("/") ? %(absolute $dir) : %(relative $dir));
  }
  String root = Compiler.package_directory(c.package_source_dirs, canonical);
  String package = root && Compiler.is_package_source(root, canonical)
                 ? Path.basename(root)
                 : _package_owns(c, canonical) ? c.package : NULL;
  int source = Path.is_x2c_source(canonical);
  dirs.push(source && package ? %(package $package) : %(package));
  return dirs.list_free();
}

/* A stored part is a home-portable include path or the sorted rows of a
   declaration map with bindings renumbered. */
static Var _stored_part(Var part, Map identities) {
  if (part is not <map>) return Compiler.portable_path(part);
  Array rows = [];
  foreach (Var (key, value), part.map()) rows.push(%($key $value));
  rows.sort();
  return _renumber_bindings(rows.list_free(), identities);
}

static List _stored_dependencies(Map dependencies) {
  Array rows = [];
  foreach (Var (path, hash), dependencies)
    rows.push(%(${Compiler.portable_path(path)} $hash));
  rows.sort();
  return rows.list_free();
}

static List _stored_meta_hashes(Map hashes) {
  Array rows = [];
  foreach (Var (spelling, hash), hashes) rows.push(%($spelling $hash));
  rows.sort();
  return rows.list_free();
}

/* A cold walk numbers bindings from wherever the shared counter stands, which
   depends on the files walked before it. An interface renumbers them in order
   of first appearance, keeping equal bindings equal. */
static List _renumber_bindings(List node, Map identities) {
  match (node) {
    case %(meta-hashes ?provider ?(Map hashes)):
      return %(meta-hashes $provider ${_stored_meta_hashes(hashes)});
  }
  String spelling = NULL;
  if (Ast.try_binding(node, NULL, spelling)) {
    Var identity = identities.setdefault(node, identities.len() + 1);
    return Ast.binding(identity, spelling);
  }
  Var child;
  $ast.rewrite_children(
    node, child, _renumber_bindings(child, identities));
}

// linked prelude

/** Returns the interface record text of each prelude component the
    compiler links, by home-portable path: the datum its `.xi` holds after
    the compiler identity. Each is walked cold by a compiler of its own, so
    the records hold this compiler's collection rather than a table linked
    into it; the unit's own entries for them are restored afterwards. A
    record the interface grammar cannot spell is left out. */
Map Compiler.linked_prelude_records(Compiler c) {
  Map records = {}, saved = {};
  foreach (String source, _linked_prelude_sources()) {
    String canonical = _canonical_path(%"${x2c_get_root()}/$source");
    saved[canonical] = _process_cache()[canonical];
    (void) _process_cache().del(canonical);
  }
  Compiler walker = Compiler.new();
  walker.sources = c.sources;
  walker.include_dirs = c.include_dirs;
  walker.filename = c.filename;
  $let(interface_mirror, NULL)
    foreach (String source, _linked_prelude_sources()) {
      String path = %"${x2c_get_root()}/$source";
      String canonical = _canonical_path(path);
      Map visited = {};
      visited[canonical] = 1;
      _walk_apart(walker, canonical, _runtime_text(walker, path), {}, visited);
      String text = _record_text(
        _stored_record(canonical, _process_cache()[canonical]));
      if (text) records[Compiler.portable_path(canonical)] = text;
    }
  foreach (Var (canonical, entry), saved)
    if (entry is <list>) _process_cache()[canonical] = entry;
  return records;
}

static macro Expression $linked.prelude() => $(_x2c.prelude.linked);

/* The record texts this compiler was translated with, by home-portable
   path. */
static Map linked_records = NULL;

/* The record linked for `canonical`, read as its interface would be, or
   NULL. */
static List _linked_record(String canonical) {
  if (!linked_records) {
    _process_cache();
    $scope(&process_cache_scope) linked_records = $linked.prelude();
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
  Buffer out = $auto(Buffer.new(0));
  if (datum_write(out, record, 0)) return out;
  return NULL;
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
