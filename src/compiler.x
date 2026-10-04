/*  compiler.x -- one x2c unit's translation state and its two parses

    Copyright (c) 2025 Gary William Flake.

    A `Compiler` owns the translation state of one unit: its token cursor,
    symbol table, and declaration state. Collection parses the unit
    shallowly, skipping function bodies; the full parse produces its AST.
    The related compilers of one unit share its package registries,
    generated names, and binding numbers. The symbol table is `Sym`, in
    `symbols.x`.

    Diagnostics may exit immediately or raise `<malformed>` while a recovery
    boundary is active.
*/
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "tokenizer.x"
#include "ast.x"
#include "type.x"
#include "logger.x"
#include "sourceview.x"
#include "meta.x"

/** Names the positioned diagnostic store routed by a `Compiler`. */
typedef struct Diagnostics *Diagnostics;

/** Describes the `#!` script unit a translation unit was started from: its
    canonical path, its first line as written, and whether it defines `main`
    itself. Every compiler of that unit shares one record, so collection sees
    the same script settings the full parse does.
*/
typedef struct ScriptUnit {
  String path, shebang;
  int defines_main;
} *ScriptUnit;

/** Holds scope-owned generated-name state shared by related compilers.

    `Compiler.new` initializes every valid instance; callers borrow it from
    the compiler rather than constructing or freeing it. `next_binding` is
    the last binding identity issued in the translation unit: collection,
    shadow, package, and full-parse compilers all draw from it, so a binding
    number names one live declaration across every symbol table in the unit.
    Rows replayed from an interface keep that interface's own numbering,
    which starts at 1. A file walked cold restores the counter afterwards,
    so the unit reuses the numbers its rows took. Either way a replayed row's
    number identifies a declaration only within that file's rows.
*/
typedef struct GenNames {
  Map counters, adapters, file_scope_owners;
  int next_binding;
} *GenNames;

/** Holds the three mutable maps that form one lexical semantic scope.

    Active scopes have initialized maps. The zero value is only the sentinel
    returned when an empty scope stack is popped.
*/
typedef struct SymScope {
  Map symbols, bindings, enumerators, macros;
} SymScope;

/** Names the scope-owned semantic table belonging to one compiler. */
typedef struct Sym *Sym;

/** Holds mutable state for one source translation.

    The structure, its state, and its owned compile-time `Lisp` session belong
    to the current `Scope`. `Compiler.free_lisp` permits early session cleanup;
    otherwise Scope teardown releases it. All Lisp calls must return first.
*/
typedef struct Compiler {
  String filename, text, root_dir;
  /* Package-mode unit: NULL outside. package_dirs holds the registered
     --package-dir roots, package_roots the directory of every package this
     unit has already collected, package_aliases the resolution-only
     spelling alias -> package name, package_members each `with` local
     spelling -> (package member), and package_exports each collected
     package's exported macro imports in its include order. */
  String package, List package_dirs;
  Map package_roots, package_aliases, package_members, package_exports;
  Token token;
  // Optional end of supplied input; NULL keeps ordinary file diagnostics.
  Token input_boundary;
  Tokenizer tokenizer;
  /* For the host preprocessor's merged output, the file each region came
     from, as `(position text-line file line)` rows; NULL otherwise. */
  Array line_markers;
  List return_type, include_dirs;
  // Canonical dependency path -> content hash for compile-time text reads,
  // or 1 for dependencies whose contents are not embedded in generated C.
  Map deps;
  List aggregate_type, macro_stack, declaration_effects, Sym sym;
  /* The last frozen `macro_stack`, reused while that List and every pool
     level live; one expansion's declarations share one stack. */
  List frozen_stack_key;
  Var frozen_stack;
  unsigned long frozen_stack_epoch;
  /* The last binding identity issued before the outermost active expansion
     began; a later identity was introduced by that expansion. */
  int expansion_floor;
  SymScope params;
  Map key_ids, macros, kw_aliases;
  /* `#define` names this unit has passed, for the literal warning and for
     declaration prefixes: the `List` of specifier words of a body made of
     specifiers and attributes, `<string>` for a string literal,
     `<annotation>` for a function-like attribute macro, `<wrapper>` for one
     that wraps its parameter in prefixes, else 1. */
  Map object_macros;
  /* The open conditional groups at the current top-level form, each an
     `(id arm state)` entry, so one function defined in two arms of one `#if`
     is one definition. `arm_stacks` maps each conditional directive's token
     index to the groups open after it. */
  List arms;
  Map arm_stacks;
  /* Token indices around attributes that can change native record layout. */
  Array layout_marks, packed_marks;
  /* The cursor after a governed statement took the directives before it,
     which the following item must not read again. */
  Token directives_taken;
  // Import paths already applied to this .x file's alias map.
  Map kw_seen;
  Map protocols, conforms, protocol_helpers;
  // Answers derived from the occurrence and adoption tables. Publishing a
  // protocol or an adoption changes what these would say, so the whole map
  // is dropped there rather than invalidated key by key.
  Map proto_cache;
  // Visible protocol adoptions indexed by base and participant.
  Map adoptions;
  Map macro_holes;
  Map local_macro_captures;
  // Depth of macro value applications being bound; their transactions
  // also cover effects and code-value carriers are consumed.
  int macro_application;
  List lambda_scopes;
  Array match_types;
  // Import path -> declared alias map, or 1 when no aliases need replay.
  Map imports;
  /* While the full parse runs, the imports each file the unit includes
     delivers at its include line, by the file's canonical path. */
  Map included_exports;
  Map init_tokens, static_init_deps, fn_defs;
  Array id_keys, inits;
  String init_fn, fini_fn;
  Array early_decls, int prelude;
  /* `meta` function definitions the unit's macro imports contributed. Their
     compile-time forms are already installed; these are the runtime forms,
     kept until the unit is parsed and only then emitted where it reaches
     them. */
  Array meta_defs;
  /* `meta_comptime` names the `meta` functions that reach a `Meta`
     operation and so have no runtime form at all: no unit emits one.
     `meta_regions` maps each installed one to its region summary, which
     the lifetime check of a later `meta` function reads at its calls.
     `meta_hashes` maps each function definition to the hash of its text,
     which a `meta` definition and its copy linked into the compiler must
     share. Collection hashes this unit's bodies before they are parsed;
     `meta_calls` lists each parsed definition's referenced names. */
  Map meta_comptime, meta_regions, meta_hashes, meta_calls;
  /* Native functions that included units advertise with `meta`, by name,
     holding each declared signature. A function binds into the macro
     session the first time compile-time code calls it. */
  Map native_meta;
  /* The unit's top-level nodes parsed so far, and its `meta` group in
     source order: each bodied `meta` function as `(function FN NAME
     TYPE)`, and while the project meta build parses the unit or the REPL
     stages it, each `meta static` value as `(static DECLARATION)` and each
     compile-time import as `(import NODES META-DEFS)`, the counts of
     `unit_nodes` and `meta_defs` after it, and while the project meta
     build parses it, each placeholder for a call left for the translation
     as `(later PLACEHOLDER)`. `meta_group_bound` holds the
     names the REPL bound to staged native code, the modules it reset, and
     each bodyless `meta` prototype nothing supplies. */
  Array unit_nodes, meta_group;
  Map meta_group_bound;
  /* One more than the helper table whose group the project meta build is
     parsing this unit for, or zero for an ordinary parse. */
  int meta_build;
  int runtime_inc, runtime_hdrs, collect_protocols, shallow, source_private;
  /* Whether the source is in the indentation syntax whatever its name, as
     when collection parses a segment of a file whose pragma it saw. */
  int layout;
  /* Whether the body being parsed belongs to a `meta` function, which is
     what lets a call to a compile-time-only one be refused everywhere
     else. */
  int meta_body;
  /* Where the expression statement being parsed starts. A meta call there
     that the statement's `;` ends is evaluated as the statement. */
  Token meta_statement;
  /* A collection pass or macro import whose protocol registries are
     installed from the collected symbols on first use;
     `Compiler._install_imports` owns the installation. */
  int import_protocols;
  int in_pattern, match_is, runtime_literals, inline_header;
  int builtin_defs, in_proto, macro_count, recovery_depth;
  int declaration_projection, declaration_produced;
  // Set when a cleanup region needs the exception runtime declarations.
  int needs_exception;
  int local_macro_capture_scopes;
  // Linkage groups that earlier segments of the collected file left open.
  int open_linkage;
  String fn_name, Diagnostics diagnostics, Array braces, import_stack;
  // Where each line of `lines_text` starts, for showing diagnostic lines.
  String lines_text, Array line_starts;
  // The unit's script record, and the same record on the compiler whose own
  // file is that script; both NULL for an ordinary unit.
  ScriptUnit unit_script, script;
  Lisp macro_lisp, String import_src, int borrowed_lisp;
  int inherited_lisp;   // the shared session evaluated this import
  GenNames names;
  Array origins, int origin, source_map;
  // The request view outlives the unit; semantic stores die with this unit.
  SourceView sources;
  int source_facts, source_primary;
  Array source_occurrences;
  Map source_definitions, source_declarations, source_texts;
} *Compiler;

/** Holds one reversible semantic transaction in caller storage.
    The zero value is inactive. Keep an active transaction in one object;
    copying it does not coordinate completion. The symbol table's undo log
    holds the rows it may restore from `mark`; the staged generated-name
    counters and other snapshots live in the Scope used to begin it.
*/
typedef struct SymTxn {
  Compiler c;
  int scope_index, next_binding, active, String initializer_name;
  String shutdown_name, Map counters;
  int local_macro_names, mark;
  SymScope scope;
  Map statics, binding_facts;
  Map source_definitions;
  int source_occurrences;
  /* A macro value application also stages producer effects: adapters,
     base bindings, early declarations, initializers, origins and errors. */
  int extended, Map adapters;
  int early_count, init_count, origin_count, origin, needs_exception;
} SymTxn;

#include "diagnostics.x"
#include "symbols.x"
#include "preprocess.x"

/* Lambda captures store non-reference values as Var, so traversal callbacks
   that carry the compiler need this raw pointer crossing. The pointee and its
   lifetime stay with the caller. */
/** Boxes the compiler's pointer; the caller keeps the compiler. */
Var Compiler.var(Compiler c) => (Var) { .p64 = c };

/** Recovers the compiler pointer boxed by `Compiler.var`. */
Compiler Var.compiler(Var value) => value.p64;

protocol Var(Compiler) as void *;
#pragma private
$(import "../src/grammar.xmacro")

#include "utils.x"
#include "parse.x"
#include "protocol.x"
#include "macros.x"
#include "stage.x"
#include "meta-group.x"
#include "meta-helper-client.x"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

$(import "../src/compiler-reports.xmacro")

// shallow collection

/** Collects file-scope declarations into `globals` without parsing bodies. */
void Compiler.shallow_parse(Compiler c, Map globals) {
  c.macros = {};
  c.kw_aliases = {};
  c.kw_seen = {};
  c.import_stack.clear();
  c.sym.reset(globals);
  c._shallow_parse_loop();
  c._check_unmatched_braces();
}

/** Collects declarations with reads over `base` then `overlay`.

    Writes go to `overlay`, which captures exactly what this translation
    contributes above `base`.
*/
void Compiler.shallow_parse_overlay(Compiler c, Map base, Map overlay) {
  if (c.macros == NULL || !c.macros.len()) c._start_macros();
  c.sym.reset_overlay(base, overlay);
  c._shallow_parse_loop();
  // Only linkage groups remain open; a later segment of the file closes them.
  c.open_linkage += c.braces.len();
}

// A unit with no macros yet starts its macro, keyword, and import state.
static void Compiler._start_macros(Compiler c) {
  c.macros = {};
  if (c.kw_aliases == NULL) c.kw_aliases = {};
  if (c.kw_seen == NULL) c.kw_seen = {};
  c.imports = {};
  c.import_stack.clear();
}

static void Compiler._shallow_parse_loop(Compiler c) {
  c.start_collection();
  c.braces.clear();
  while (c.peek(0) != <eof>) {
    Token start = c.token;
    (void) c.parse_top_level_mode(1);
    _debug_tokens(start, c.token);
  }
  /* Definitions after the last declaration, as before an include, still
     define macros for the segments that follow. */
  foreach (List directive, c.leading_preproc())
    c.note_object_macro(directive.cadr());
  c.shallow = 0;
}

/** Starts a collection pass with the built-in macros. It parses no bodies,
    and an import it reads installs the protocols visible to it when a
    template or `meta` body first asks for one. */
void Compiler.start_collection(Compiler c) {
  c.install_builtin_macros();
  c.rebuild_protocols(NULL);
  c.import_protocols = 1;
  c.conforms = {};
  c.shallow = 1;
}

static void _debug_tokens(Token start, Token end) {
  if (!log_should_log(<debug>, <tokenizer>)) return;
  for (Token tok = start; tok < end; tok++)
    if (tok.type != <space> && tok.type != <comment> && tok.type != <preproc>)
      $report.debug.token(tok);
}

/** Collects a macro or keyword definition while deferring its diagnostics.
    Returns one on success; malformed syntax skips to end of file and returns
    zero so the full parse can report it.
*/
int Compiler.collect_compile_time_definition(Compiler c, int keyword) {
  int failed = 0;
  DiagnosticsHold hold = c.diagnostics.hold();
  $let(c.recovery_depth, c.recovery_depth + 1) {
    try {
      if (keyword) c.parse_keyword_definition();
      else c.parse_macro_definition();
    }
    catch %(malformed *): failed = 1;
  }
  c.diagnostics.release(hold, 0);
  if (failed) while (c.peek(0) != <eof>) c.next();
  return !failed;
}

/** Records declaration visibility and meta facts, then skips its body.
    The declaration is already bound by the shared top-level parser.
*/
void Compiler.finish_collected_declaration(
  Compiler c, List declaration, Token meta, int native) {
  /* Collection records the runtime function a `meta` marker precedes, the
     native binding a bodyless or `native` marker advertises, and the stub
     of a bodied one; the full parse installs the compile-time form. */
  c.record_declaration_visibility(declaration);
  /* Lexical privacy also marks a name in Sym.statics, so a static function
     is marked again as `(function name)`. File collection reads that key to
     keep the function out of what a private region publishes. */
  match (declaration)
    case %(declare ?type (bindings (bind ?binding ((fnmod *) *)))):
      if (type.type().is_static())
        c.sym.mark_static(%(function ${binding_identity_spelling(binding)}));
  if (c.peek(0) == <"{"> || c.peek(0) == <"%{"> || c._at_function_arrow())
    c._skip_body(declaration, meta, native);
  else if (c.peek(0) == <;>) {
    if (meta) c.record_native_meta_effect(declaration, meta);
    c.next();
  }
  else c.next();
}

static void Compiler._skip_body(
  Compiler c, List declaration, Token meta, int native) {
  if (native) c.record_native_meta_effect(declaration, meta);
  else if (meta) c.install_collected_meta_function(declaration, meta);
  match (declaration)
    case %(declare ? (bindings (bind ?binding ?))):
      c._note_function_body(declaration.type_from_ast(), binding);
  if (c._at_function_arrow()) {
    c.next();
    c.next();
    c._skip_shallow_expression(0);
    c.expect(<;>);
  }
  else c._shallow_block();
}

// `fn_defs` holds each non-static function the unit defines.
static void Compiler._note_function_body(Compiler c, Type type, List binding) {
  if (!type.is_function() || type.is_static()) return;
  c.fn_defs[binding_identity_spelling(binding)] = 1;
}

/** Reports whether the current two tokens are `=>`. */
int Compiler._at_function_arrow(Compiler c) =>
  c.peek(0) == <=> && c.peek(1) == <">">;

/** Skips a balanced shallow expression without consuming its terminator.
    A top-level comma also terminates the expression when `stop_at_comma` is
    nonzero.
*/
void Compiler._skip_shallow_expression(Compiler c, int stop_at_comma) {
  for (Symbol type = c.peek(0);
       type != <eof> && type != <;> && (!stop_at_comma || type != <,>);
       type = c.peek(0)) {
    if (type.group_step() > 0) c.token = c.token.after_group();
    else c.next();
  }
}

static void Compiler._shallow_block(Compiler c) {
  c.next();
  for (Symbol peek = c.peek(0); peek != <"}">; peek = c.peek(0)) {
    if (peek == <eof>)
      $report.parse.token_eof(c);
    if (peek == <"{"> || peek == <"%{"> || peek == <"${"> || peek == <"@{">)
      c._shallow_block();
    else c.next();
  }
  c.expect(<"}">);
}

/* declaration production

   A declaration producer's source effects wait until production needs
   their state. Collection retains the bundle a producer returns with its
   token span, and the full parse replays that bundle. */

/** Queues a source Lisp form until declaration production needs its state.
    Files without declaration producers keep ordinary full-parse evaluation. */
void Compiler.queue_declaration_effect(
  Compiler c, String form, Token first, Token after) {
  List key = c._declaration_source_key(first);
  String context = c.import_stack.len() ? c.import_stack[-1] : c.filename;
  c.declaration_effects = cons(
    %($key ${after.pos} $form ${c.freeze_declaration_syntax(first)} $context),
    c.declaration_effects);
}

static List Compiler._declaration_source_key(Compiler c, Token token) {
  String path = home_portable_path(absolute_path(c.filename));
  return %("source-node" (declaration $path ${token.pos}));
}

/** Runs pending effects for declaration production or CPP macro evaluation. */
void Compiler.run_declaration_effects(Compiler c) {
  List effects = c.declaration_effects.reverse();
  c.declaration_effects = NULL;
  foreach (List effect, effects) {
    (List key, int end, String form, Var site, String context) = effect;
    $let(c.filename, c._effect_file(key)) {
      c.import_stack.push(context);
      defer c.import_stack.take_last();
      Token token = c.thaw_declaration_syntax(site);
      c.evaluate_declaration_effect(form, token);
      if (c.collect_protocols)
        c.sym.set(key, %(declaration-source $end (declaration-bundle (rows))));
    }
  }
}

static String Compiler._effect_file(Compiler c, List key) {
  match (key)
    case %("source-node" (declaration ?path ?)):
      return _declaration_path(path, 1);
  return c.filename;
}

/** Expands the file-scope unit macro at the cursor for collection and
    reports whether it did. A required expansion reports its errors. A tried
    expansion that fails keeps nothing and leaves the cursor at the
    invocation, so collection skips it and the full parse reports it.
*/
int Compiler.collect_unit_macro(Compiler c) {
  Symbol collection = c.macro_invocation_collection();
  if (collection == <tried>) return c._try_unit_macro();
  if (collection == <required>) c._expand_unit_macro();
  return collection == <required>;
}

static int Compiler._try_unit_macro(Compiler c) {
  Token first = c.token;
  int failed = 0;
  SymTxn transaction = c.begin_semantic_transaction();
  DiagnosticsHold hold = c.diagnostics.hold();
  $let(c.recovery_depth, c.recovery_depth + 1) {
    try c._expand_unit_macro();
    catch %(malformed *): failed = 1;
  }
  c.diagnostics.release(hold, 0);
  if (!failed) transaction.commit();
  else {
    transaction.rollback();
    c.token = first;
  }
  return !failed;
}

/* The expansion retains its declarations for collection, and its private
   helpers remain available to later invocations. Generated-name counters
   are restored when the full parse must expand it again. */
static void Compiler._expand_unit_macro(Compiler c) {
  Map counters = c.names.counters;
  c.names.counters = counters.copy();
  Token first = c.token;
  List syntax = c.parse_top_level();
  int retained = c._retain_bundle(syntax, first, c.token);
  /* The full parse expands this unit again. Keep the declarations needed
     by later shallow invocations, but do not count its generated names
     twice. */
  if (!retained) c.names.counters = counters;
}

/* The owning source records one declaration production, including its exact
   token span. Full parsing consumes that production instead of invoking its
   compile-time producer again. Ordinary Unit macros retain their old path. */
static int Compiler._retain_bundle(
  Compiler c, List syntax, Token first, Token after) {
  match (syntax) {
    case %(seq ?only): return c._retain_bundle(only, first, after);
    case %(declaration-bundle (rows *)): {
      List frozen = c.freeze_declaration_syntax(syntax);
      c.sym.set(
        c._declaration_source_key(first),
        %(declaration-source ${after.pos} $frozen));
      return 1;
    }
  }
  return 0;
}

static List Compiler._replay_bundle(Compiler c) {
  List source = c.sym.get(c._declaration_source_key(c.token));
  match (source)
    case %(declaration-source ?(int end) ?syntax): {
      List thawed = c.thaw_declaration_syntax(syntax);
      List bound = c.bind_syntax(thawed, AST_UNIT, NULL);
      while (c.peek(0) != <eof> && c.token.pos < end) c.next();
      return bound;
    }
  return NULL;
}

/* retained declaration syntax

   Declaration syntax outlives the segment that parsed it, in the process
   cache and in `.xi` interfaces. Freezing turns tokens and origin indices
   into portable rows, and thawing rebuilds them in the current parse. */

/** Retains declaration syntax across source segments and cached interfaces.
    Tokens and origin indices become portable source data; marker-shaped user
    Lists are escaped so thawing preserves their values.
*/
Var Compiler.freeze_declaration_syntax(Compiler c, Var syntax) {
  if (syntax is not <list> || syntax.is_nil()) return _freeze_leaf(syntax);
  match (syntax) {
    case %(macrodef *rows): return c._declaration_macro(rows, 0);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source ${_declaration_path(path, 0)} $begin $end)
        ${c.freeze_declaration_syntax(node)});
    case %(at ?(int origin) ?node): return c._freeze_origin(origin, node);
  }
  return c._freeze_rows(syntax);
}

// A leaf that a List cannot carry as itself becomes a marker row.
static Var _freeze_leaf(Var syntax) {
  if (syntax is void) return %(declaration-void);
  if (syntax is <symbol> && !syntax.symbol())
    return %(declaration-empty-symbol);
  if (syntax.is_atom() && !Atom.bare_spelling(syntax.str()))
    return %(declaration-atom ${syntax.str()});
  if (syntax is not <token>) return syntax;
  Token token = syntax;
  return %(declaration-token ${token.type.str()} ${token.text}
            ${token.line} ${token.col} ${token.len} ${token.pos});
}

// An origin index freezes as the location it names in this parse.
static List Compiler._freeze_origin(Compiler c, int origin, Var node) {
  List location = c.origin_location(origin);
  if (!location) return %(at m-origin ${c.freeze_declaration_syntax(node)});
  return %(declaration-origin ${_declaration_location(location, 0)}
            ${c.freeze_declaration_syntax(node)});
}

// A List whose head is a marker is escaped, so thawing keeps its value.
static List Compiler._freeze_rows(Compiler c, List syntax) {
  Array rows = [];
  foreach (Var row, syntax) rows.push(c.freeze_declaration_syntax(row));
  match (syntax)
    case %((!or declaration-void declaration-empty-symbol declaration-atom
                declaration-token declaration-origin declaration-list) *):
      return %(declaration-list @{rows.list_free()});
  return rows.list_free();
}

/** Returns `freeze_declaration_syntax` of the active macro stack. */
Var Compiler.freeze_macro_stack(Compiler c) {
  unsigned long epoch = Pool.epoch();
  if (c.macro_stack != c.frozen_stack_key || epoch != c.frozen_stack_epoch ||
      c.frozen_stack is void) {
    c.frozen_stack = c.freeze_declaration_syntax(c.macro_stack);
    c.frozen_stack_key = c.macro_stack;
    c.frozen_stack_epoch = epoch;
  }
  return c.frozen_stack;
}

/** Restores a retained declaration recipe in the current parsing lifetime. */
Var Compiler.thaw_declaration_syntax(Compiler c, Var syntax) {
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  match (syntax) {
    case %(declaration-list *rows): return c._thaw_rows(rows);
    case %(macrodef *rows): return c._declaration_macro(rows, 1);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source ${_declaration_path(path, 1)} $begin $end)
        ${c.thaw_declaration_syntax(node)});
    case %(declaration-void): return void;
    case %(declaration-empty-symbol): return (Symbol) 0;
    case %(declaration-atom ?spelling): return Atom.intern(spelling);
    case %(declaration-token ?type ?text ?line ?column ?length ?position):
      return _thaw_token(type, text, line, column, length, position);
    case %(declaration-origin ?location ?node):
      return c._thaw_origin(location, node);
  }
  return c._thaw_rows(syntax);
}

static List Compiler._thaw_rows(Compiler c, List rows) {
  Array values = [];
  foreach (Var row, rows) values.push(c.thaw_declaration_syntax(row));
  return values.list_free();
}

static Token _thaw_token(
  Var type, Var text, Var line, Var column, Var length, Var position) {
  Token token = Scope.calloc(1, sizeof(struct Token));
  *token = (struct Token) {
    .text = text, .type = Symbol.new(type.string()), .line = line,
    .col = column, .len = length, .pos = position};
  return token;
}

// A frozen location becomes a new row of this parse's origin table.
static List Compiler._thaw_origin(Compiler c, List location, Var node) {
  match (location)
    case %((file ?file) (line ?line) (column ?column) (length ?length)
           (position ?position)):
      c.origins.push(%(source $file $line $column $length $position));
  return %(at ${c.origins.len()} ${c.thaw_declaration_syntax(node)});
}

static List Compiler._declaration_macro(Compiler c, List rows, int thaw) {
  Array out = [];
  foreach (List row, rows) out.push(c._macro_row(row, thaw));
  return %(macrodef @{out.list_free()});
}

static List Compiler._macro_row(Compiler c, List row, int thaw) {
  match (row)
    case %(origin ?location):
      return %(origin ${_declaration_location(location, thaw)});
  return thaw ? c.thaw_declaration_syntax(row)
              : c.freeze_declaration_syntax(row);
}

static List _declaration_location(List location, int thaw) {
  Array rows = [];
  foreach (List row, location) {
    match (row)
      case %(file ?path):
        row = %(file ${_declaration_path(path, thaw)});
    rows.push(row);
  }
  return rows.list_free();
}

static String _declaration_path(String path, int thaw) {
  if (!path || path.startswith("<")) return path;
  return thaw ? home_absolute_path(path) : home_portable_path(path);
}

/* declaration defaults

   A declaration producer can offer defaults: functions that bind only when
   no other declaration takes their name, and constructors that forward to
   a parent's constructor. The owning file selects them after all its
   segments. */

/* One selection of a file's defaults. `c`, a shadow compiler, binds them
   over the file's collected symbols. `sources` holds one
   `(declarations key end rows)` entry per production, and `pending` the
   children whose forwarded constructors wait for their parent's
   constructor. */
typedef struct Defaults {
  Compiler c, Array parts, sources;
  Map definitions, pending;
} Defaults;

/** Selects the owning file's declaration defaults after all its segments.
    The selected signatures join ordinary declarations before protocol and
    body binding; discarded candidates never bind their bodies. Returns added
    signatures for the caller to retain in the header-cache lifetime.
*/
Map Compiler.select_declaration_defaults(
  Compiler c, String path, Map symbols, Array parts, Map definitions) {
  Compiler shadow = Compiler.new_shared(c);
  defer c.close_child(shadow);
  shadow._prepare_shadow(c, path, symbols);
  Array sources = [];
  Map pending = {};
  Defaults d = {
    .c = shadow, .parts = parts, .sources = sources,
    .definitions = definitions, .pending = pending};
  foreach (Var part, parts) if (part is <map>) d.produce(part);
  d.select();
  d.forward();
  d.store(symbols);
  Map additions = shadow.sym.current_symbols();
  symbols.merge(additions);
  c.merge_source_declarations(symbols, additions);
  c.fn_defs.merge(shadow.fn_defs);
  definitions.merge(shadow.fn_defs);
  return additions;
}

/* The shadow binds over the file's collected symbols in an overlay,
   without parsing, in the unit's Lisp session and meta group. */
static void Compiler._prepare_shadow(
  Compiler c, Compiler owner, String path, Map symbols) {
  c.filename = path;
  c.macro_lisp = owner.macro_lisp;
  c.borrowed_lisp = c.macro_lisp != NULL;
  c.share_meta_group(owner);
  c.sym.reset_overlay(symbols, {});
  c.rebuild_protocols(symbols);
  c.conforms = {};
  c.shallow = 1;
  c.declaration_projection = 1;
}

// A part's productions run in source order.
static void Defaults.produce(Defaults &d, Map declarations) {
  Array ordered = [];
  foreach (Var (key, value), declarations)
    match (key)
      case %("source-node" (declaration ? ?position)):
        ordered.push(%($position $key $value));
  ordered.sort();
  foreach (List entry, ordered) {
    (Var position, Var key, Var value) = entry;
    (void) position;
    match (value)
      case %(declaration-source ?end (declaration-bundle (rows *rows))): {
        rows = d.c.thaw_declaration_syntax(rows);
        Array produced = [];
        d.c._produce(rows, produced);
        d.sources.push(%($declarations $key $end ${produced.list_free()}));
      }
  }
}

/* A pending row runs its recipe under the macro stack and privacy of its
   construction, and the rows it generates are produced in turn. */
static void Compiler._produce(Compiler c, List rows, Array selected) {
  foreach (List row, rows) {
    match (row)
      case %(declaration-pending ?callback ?arguments
               ?construction ?privacy): {
        $let(c.macro_stack, c.thaw_declaration_syntax(construction))
        $let(c.source_private, privacy)
          c._produce(c._generated_rows(callback, arguments), selected);
        continue;
      }
    selected.push(row);
  }
}

// A recipe's rows: the children of a sequence or bundle, or its one node.
static List Compiler._generated_rows(Compiler c, Var callback, Var arguments) {
  List generated = c.bind_syntax(
    c.evaluate_declaration_recipe(callback, arguments), AST_UNIT, NULL);
  List additions = %($generated);
  match (generated) {
    case %(seq *children): additions = children;
    case %(declaration-bundle (rows *children)): additions = children;
  }
  return additions;
}

/* Each production selects its defaults, and a forwarded constructor
   waits for its parent's constructor. */
static void Defaults.select(Defaults &d) {
  for (size_t index = 0; index < d.sources.len(); index++) {
    (Map declarations, Var key, Var end, List rows) = d.sources[index];
    List selected = d._select_rows(rows);
    foreach (List row, selected)
      match (row)
        case %(declaration-forward ?child *): d.pending[child] = 1;
    d.sources[index] = %($declarations $key $end $selected);
  }
}

static List Defaults._select_rows(Defaults &d, List rows) {
  Compiler c = d.c;
  Array selected = [];
  foreach (List row, rows) {
    match (row)
      case %(declaration-default ?function ?construction ?privacy): {
        $let(c.macro_stack, c.thaw_declaration_syntax(construction))
        $let(c.source_private, privacy) {
          Var syntax = d._unless_taken(function);
          if (syntax is not void) selected.push(c._bind_default(syntax));
        }
        continue;
      }
    selected.push(row);
  }
  return selected.list_free();
}

/* Returns the function to bind for a default, named through its macro
   slot, or void when a declaration already takes its name. */
static Var Defaults._unless_taken(Defaults &d, List syntax) {
  match (syntax)
    case %(function ?return_type (bind ?name ?modifiers) ?body): {
      name = d.c.evaluate_macro_slot(name);
      String spelling = binding_identity_spelling(name);
      match (name) {
        case %(?(String literal)): spelling = literal;
        case %("x2c.ident" ?(String literal)): spelling = literal;
      }
      if (spelling && d._taken(spelling)) return void;
      return %(function $return_type (bind $name $modifiers) $body);
    }
  return syntax;
}

/* A default yields to any declaration of its name except a bodyless,
   non-static function prototype in the default's own file, which the
   default then completes. */
static int Defaults._taken(Defaults &d, String spelling) {
  Compiler c = d.c;
  List key = %($spelling);
  Type declared = c.sym.get(key);
  if (!declared) return 0;
  if (!declared.is_function() || spelling in d.definitions ||
      spelling in c.fn_defs || %(function $spelling) in c.sym.file_statics())
    return 1;
  foreach (Var part, d.parts) if (part is <map> && key in part.map()) return 0;
  return 1;
}

static List Compiler._bind_default(Compiler c, List syntax) {
  if (c.source_private)
    match (syntax)
      case %(function ?type ?declarator ?body):
        if (!type.type().is_static())
          syntax = %(function (static @type) $declarator $body);
  return c.bind_syntax(syntax, AST_UNIT, NULL);
}

/* Forwarded constructors bind as their parents' constructors complete; a
   round that completes none leaves a parent that never will. */
static void Defaults.forward(Defaults &d) {
  int remaining = d.pending.len();
  while (remaining) {
    int previous = remaining;
    remaining = 0;
    for (size_t index = 0; index < d.sources.len(); index++) {
      (Map declarations, Var key, Var end, List rows) = d.sources[index];
      rows = d._forward_rows(rows, remaining);
      d.sources[index] = %($declarations $key $end $rows);
    }
    if (remaining && remaining == previous)
      $report.type.ctor_parent(d.c);
  }
}

static List Defaults._forward_rows(Defaults &d, List rows, int &remaining) {
  Array selected = [];
  foreach (List row, rows) {
    match (row)
      case %(declaration-forward ?child ?parent ?member ?fallback ?privacy): {
        List bound = NULL;
        $let(d.c.source_private, privacy)
          bound = d._forwarded(child, parent, member, fallback);
        if (!bound) {
          remaining++;
          selected.push(row);
        }
        else {
          d.pending.del(child);
          if (bound.car() != <seq>) selected.push(bound);
        }
        continue;
      }
    selected.push(row);
  }
  return selected.list_free();
}

/* Binds the constructor `child_member` that forwards to the parent's
   `member`. It is `(seq)` when that name is already declared, the fallback
   when the parent has no such member, and NULL while the parent's own
   constructor is still pending. */
static List Defaults._forwarded(
  Defaults &d, Type child, Type parent, String member, List fallback) {
  Compiler c = d.c;
  String name = %"${child.car()}_$member";
  if (c.sym.get(%($name))) return %(seq);
  List method = c.resolve_postfix_member(parent, %($member), <.>, 1);
  if (!method) {
    if (parent in d.pending) return NULL;
    return fallback ? c._bind_default(fallback.car()) : NULL;
  }
  List binding = NULL, Type signature = NULL;
  match (method)
    case %(method ?target ?type): {
      binding = target;
      signature = type;
    }
  if (!signature) return NULL;
  return c._bind_default(c._forwarder(name, child, binding, signature));
}

// The forwarding constructor passes each argument on and casts the result.
static List Compiler._forwarder(
  Compiler c, String name, Type child, List binding, Type signature) {
  List types = NULL;
  match (signature) case %((func ?parameters) *): types = parameters;
  Array parameters = [], arguments = [];
  int index = 0;
  foreach (Var type, types) {
    if (type == <...>)
      $report.type.ctor_variadic(c, name);
    if (type == %(void)) continue;
    String argument = %"argument$index";
    index++;
    parameters.push(%(param $type (bind ($argument) ())));
    arguments.push(%(expr $type (ident ($argument))));
  }
  List call = %(expr ()
    (call (expr $signature (ident $binding)) (args @{arguments.list_free()})));
  List body = %(block (return () (expr () (cast $child $call))));
  return %(function $child
    (bind ($name) ((fnmod (params @{parameters.list_free()})))) $body);
}

/* The selected rows replace each production's bundle in its part and in
   the unit's symbols. */
static void Defaults.store(Defaults &d, Map symbols) {
  foreach (List source, d.sources) {
    (Map declarations, Var key, Var end, List rows) = source;
    declarations[key] = d.c.freeze_declaration_syntax(
      %(declaration-source $end (declaration-bundle (rows @rows))));
    symbols[key] = declarations[key];
  }
}

/* the parse driver

   A full parse reads the unit's top-level forms in source order. A form
   that fails is skipped whole, so one error does not hide the next. */

/* One full parse of a unit. A script unit that does not define `main`
   hoists its statements: `statements` holds each run's first and
   past-the-end token index, `runs` counts the runs, `first` is where the
   first one starts, and `gap` is the index after the last form, where the
   next form's conditional directives begin. */
typedef struct FullParse {
  Compiler c, Array nodes, statements;
  int hoisting, gap, runs, first;
} FullParse;

/** Parses and types the positioned source against `globs`.

    The result is a source-ordered top-level AST. This resets per-parse
    origins, macro state, and protocol resolution.
    `generated_symbols` publishes external adapter signatures before parsing.
*/
List Compiler.full_parse(Compiler c, Map globs, int generated_symbols) {
  Array nodes = [];
  c.unit_nodes = nodes;
  c._reset_parse(globs, generated_symbols);
  Token conflict = NULL;
  $let(c.recovery_depth, c.recovery_depth + 1)
    conflict = c._parse_forms(nodes);
  if (conflict) {
    c.token = conflict;
    c._report_script_statement();
  }
  return c._finish_parse(nodes);
}

/* A full parse starts from the unit's collected symbols, without the parse
   state that collection or an earlier parse left. */
static void Compiler._reset_parse(Compiler c, Map globs, int generated) {
  c.meta_group.clear();
  c.meta_group_bound = {};
  c.origins.clear();
  c.meta_defs.clear();
  c.meta_comptime = {};
  c.meta_regions = {};
  c.native_meta = {};
  c.inherit_library_comptime();
  c.init_tokens = {};
  c.static_init_deps = {};
  c.origin = 0;
  c.braces.clear();
  c.arms = NULL;
  c.sym.reset(globs);
  c.rebuild_protocols(globs);
  c._reset_macros();
  c.resolve_protocols();
  if (generated) c.install_generated_protocol_symbols();
  c.install_native_meta_effects(globs);
  c.included_exports = c.replay_included_package_imports(globs);
}

static void Compiler._reset_macros(Compiler c) {
  c.macros = {};
  c.kw_aliases = {};
  c.kw_seen = {};
  c.install_builtin_macros();
  if (!c.declaration_produced) c.imports = {};
  c.import_stack.clear();
  c.macro_count = 0;
  c.macro_stack = NULL;
  c.source_private = 0;
}

/* Parses every form, then the `main` that a script's statement runs
   become. Returns the first hoisted statement when a macro defined `main`
   where the token scan saw none, and NULL otherwise. */
static Token Compiler._parse_forms(Compiler c, Array nodes) {
  c._append_preproc(nodes);
  Array statements = [];
  FullParse p = {
    .c = c, .nodes = nodes, .statements = statements,
    .hoisting = c.script && !c.script.defines_main};
  loop {
    while (c.peek(0) != <eof>) if (!p.form()) break;
    if (!p.runs) return NULL;
    Token tokens = c.tokenizer.tokens;
    if ("main" in c.fn_defs) return tokens + p.first;
    c._push_conditionals(statements, p.gap, c.token - tokens);
    c._append_script_main(statements);
    p.hoisting = p.runs = 0;
  }
}

/* Parses one form, or skips a failed one whole. Returns 0 when the parse
   stops: the error limit is reached, or the skip reached the end. */
static int FullParse.form(FullParse &p) {
  Compiler c = p.c;
  Token start = c.token;
  int braces = c.braces.len();
  try {
    p.parse(start);
  }
  catch %(malformed (category ?category) *): {
    (void) category;
    if (c.diagnostics.reached_limit()) return 0;
    c._sync_top_level(start, braces);
    p.gap = c._end_index(c.tokenizer.tokens);
    c._append_preproc(p.nodes);
    return c.peek(0) != <eof>;
  }
  return 1;
}

static void FullParse.parse(FullParse &p, Token start) {
  Compiler c = p.c;
  Token tokens = c.tokenizer.tokens;
  int begin = start - tokens;
  if (p.hoisting) c._push_conditionals(p.statements, p.gap, begin);
  if (p.hoisting && c.script_statement_starts()) p.hoist(begin, tokens);
  else p.top_level(begin, tokens);
  p.gap = c._end_index(tokens);
  c._append_preproc(p.nodes);
  _debug_tokens(start, c.token);
}

// A script statement joins the runs that `main` executes.
static void FullParse.hoist(FullParse &p, int begin, Token tokens) {
  p.c.skip_script_statement();
  int end = p.c._end_index(tokens);
  p.statements.push(begin);
  p.statements.push(end);
  if (!p.runs++) p.first = begin;
}

// A retained declaration bundle replays; any other form parses.
static void FullParse.top_level(FullParse &p, int begin, Token tokens) {
  Compiler c = p.c;
  c._reject_statement();
  Ast node = c._replay_bundle();
  if (!node) node = c.parse_top_level();
  int end = c._end_index(tokens);
  if (node && node.car() == <seq>)
    foreach (List item, node.cdr()) p.add(item, begin, end);
  else if (node) p.add(node, begin, end);
}

static void FullParse.add(FullParse &p, List node, int begin, int end) {
  Token tokens = p.c.tokenizer.tokens;
  p.c._record_top_level(node, tokens + begin);
  p.c._record_span(node, begin, end);
  p.nodes.push(node);
}

// The index after the last non-trivia token before the cursor.
static long Compiler._end_index(Compiler c, Token tokens) =>
  _skip_backward(c.token - 1, tokens) + 1 - tokens;

/* The directives before the cursor join the nodes in source order, after
   they update source visibility and the unit's macro names and an include
   delivers the imports its file exports. */
static void Compiler._append_preproc(Compiler c, Array nodes) {
  List directives = c.leading_preproc();
  c.update_source_visibility(directives);
  if (c.included_exports.len()) c.import_included_exports();
  foreach (Var directive, directives) nodes.push(directive);
}

/* A failed declaration is skipped whole from its first token, because a
   report inside a body leaves the cursor where no declaration can start.
   The declaration ends at a `;` outside delimiters, at a closing delimiter
   whose next token begins a later line, such as a function body or a macro
   invocation, or at a `}` that nothing on its line continues. A `struct`
   body continues to its declarators, and a second function body on the
   same line is a second declaration. */
static void Compiler._sync_top_level(Compiler c, Token start, int braces) {
  c.token = start;
  c.braces.resize(braces);
  int depth = 0;
  while (c.peek(0) != <eof>) {
    Token token = c.token;
    c.next();
    if (!depth && token.type == <;>) return;
    int step = token.type.group_step();
    depth += step;
    if (depth < 0) depth = 0;
    Symbol next = c.peek(0);
    if (!depth && step < 0 &&
        (c.token.line > token.line ||
         (token.type == <"}"> && next != <ident> && next != <*> &&
          next != <;> && next != <,> && next != <(>)))
      return;
  }
}

static List Compiler._finish_parse(Compiler c, Array nodes) {
  if (c.meta_build) c.write_meta_build();
  c._append_meta_definitions(nodes);
  c.unit_nodes = NULL;
  List ast = nodes.list_free();
  if (c.script && !c.script.defines_main && !c.error_count())
    c._check_script_locals(ast);
  c._check_unmatched_braces();
  if (!c.error_count()) c._check_static_inits();
  return ast;
}

/* script units

   A script unit that defines `main` rejects top-level statements; one that
   does not runs them, in source order, inside a generated `main`. */

/** Skips a collected script statement, or diagnoses one beside `main`.
    Called after top-level directives establish source visibility.
*/
int Compiler.skip_collected_script_statement(Compiler c) {
  if (!c.script) return 0;
  if (!c.script.defines_main && c.script_statement_starts()) {
    c.skip_script_statement();
    return 1;
  }
  c._reject_statement();
  return 0;
}

/** Moves past one run of a script unit's statement tokens, through a `;` or
    a closing `}` outside every bracket. A statement that ends early this
    way leaves its remainder as the next run, and runs are rejoined in order.
*/
void Compiler.skip_script_statement(Compiler c) {
  for (int depth = 0; c.peek(0) != <eof>;) {
    Symbol type = c.peek(0);
    if (type == <"$(">) {
      c.token = c.token.after_group();
      continue;
    }
    depth += type.group_step();
    c.next();
    if (depth <= 0 && (type == <;> || type == <"}">)) return;
  }
}

/* A script unit either defines `main` or runs its top-level statements, so
   a statement beside `main` is the one form it rejects. */
static void Compiler._reject_statement(Compiler c) {
  if (c.script && c.script.defines_main && c.script_statement_executes())
    c._report_script_statement();
}

static void Compiler._report_script_statement(Compiler c) {
  $report.parse.script_main(c);
}

/* A file-scope conditional directive also governs the statements it
   surrounds, so a copy of each joins the statement runs in source order and
   the script body keeps the file's conditional structure. */
static void Compiler._push_conditionals(
  Compiler c, Array statements, int first, int end) {
  Token tokens = c.tokenizer.tokens;
  for (int i = first; i < end; i++) {
    Token token = tokens + i;
    if (token.type != <preproc> || !preproc_conditional_kind(token.text))
      continue;
    statements.push(i);
    statements.push(i + 1);
  }
}

/* A script unit's `main` is ordinary source the parser reads after the last
   top-level form: this template with the statement runs, in source order,
   in place of `x2c_script_statements`. The statements run in their own
   function, so the `try` that reports an uncaught error leaves their locals
   ordinary. A failed command's status becomes the exit status; any other
   uncaught error exits with 1. */
static const char *script_main =
  "static int x2c_script(int argc, char **argv, List args) {\n"
  "  (void) argc, (void) argv, (void) args;\n"
  "  x2c_script_statements\n"
  "  return 0;\n"
  "}\n"
  "int main(int argc, char **argv) {\n"
  "  try {\n"
  "    return x2c_script(argc, argv, Args.from_argv(argc, argv));\n"
  "  }\n"
  "  catch %(cmd-fail (command ?command) (status ?status) *): {\n"
  "    fprintf(stderr, \"%s: command %s failed with status %ld\\n\",\n"
  "            argv[0], command.repr().str(), status.integer());\n"
  "    return (int) status.integer();\n"
  "  }\n"
  "  catch %(?code *detail): {\n"
  "    fprintf(stderr, \"%s: %s %s\\n\",\n"
  "            argv[0], code, detail.repr().str());\n"
  "    return 1;\n"
  "  }\n"
  "}\n";

/* Replaces the token stream with a copy that ends in the script's `main`.
   The copy keeps every consumed token at its index, so recorded token
   indices stay valid, and drops the trivia already read before end of file.
   `statements` holds each run's first and past-the-end token index. */
static void Compiler._append_script_main(Compiler c, Array statements) {
  Token tokens = c.tokenizer.tokens, eof = c.token;
  long kept = c._end_index(tokens);
  Token first = tokens + statements[0].integer();
  Bytes stream = Bytes.new(sizeof(struct Token));
  stream = stream.append(tokens, kept);
  Tokenizer template = Tokenizer.new((char *) script_main, <x2c>);
  template.scan();
  for (Token token = template.tokens; token.type != <eof>; token++) {
    if (token.text == "x2c_script_statements")
      stream = _append_runs(stream, tokens, statements);
    else stream = _append_placed(stream, token, first);
  }
  stream = stream.append(eof, 1);
  c.tokenizer.tokens = stream;
  c.token = Token.skip_trivia((Token) stream + kept);
}

static Bytes _append_runs(Bytes stream, Token tokens, Array statements) {
  for (int i = 0; i < statements.len(); i += 2) {
    long start = statements[i];
    long end = statements[i + 1];
    stream = stream.append(tokens + start, end - start);
  }
  return stream;
}

/* A template token takes the first statement's position with no length, so
   a diagnostic about it names the script without reading past its text. */
static Bytes _append_placed(Bytes stream, Token token, Token first) {
  struct Token placed = *token;
  placed.line = first.line;
  placed.col = first.col;
  placed.pos = first.pos;
  placed.len = 0;
  return stream.append(&placed, 1);
}

/* A script's functions cannot see the variables declared among its
   statements, which are locals of `x2c_script`. C would report such a name
   as undeclared; this names the cause and the `static` spelling that
   shares it. */
static void Compiler._check_script_locals(Compiler c, List ast) {
  Map locals = _script_locals(ast);
  if (!locals.len()) return;
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? ?(String function)) ?)
           (block *items)):
      if (function != "x2c_script" && function != "main")
        c._check_local_uses(items, locals);
}

static Map _script_locals(List ast) {
  Map locals = {};
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? "x2c_script") ?)
        ${$source_block_content(%(*items))}):
      foreach (List item, items) match (item)
        case %(at ? (declare ? (bindings *bindings))):
          foreach (List binding, bindings) match (binding)
            case %(!or (bind (binding ? ?(String name)) ?)
                       (op = (bind (binding ? ?(String name)) ?) ?)):
              locals[name] = 1;
  return locals;
}

static void Compiler._check_local_uses(Compiler c, List items, Map locals) {
  foreach (List item, items) match (item) case %(at ?origin ?statement):
    foreach (Var name, locals.keys()) {
      Var found;
      List bindings;
      int present = statement.list().try_search(
        %(expr () ${source_identifier_content(%((binding ? $name)))}),
        found, bindings);
      if (!present) continue;
      c.origin = origin;
      $report.type.script_local(c, name);
    }
}

/* top-level definitions

   Each form the full parse reads records the facts that later checks use:
   its object and function definitions, prototypes, static initializers,
   and the token span of its source. A conflict between definitions is
   reported at `site`, the form's first token, or at the cursor for a form
   without one. */

static void Compiler._record_top_level(Compiler c, List node, Token site) {
  match (node) {
    case %(declare (!set ?declared (*)) (bindings *bindings)): {
      Type type = declared;
      c._record_objects(bindings, site);
      c._record_static_object(type, bindings);
      c._record_prototypes(type, bindings);
    }
    case %(function ?return_type
           (!set ?target (bind ?binding *)) ?): {
      List declaration = %(declare $return_type (bindings $target));
      c._record_definition(declaration.type_from_ast(), binding, site);
    }
  }
}

/* An initializer makes a file-scope declaration a definition; a tentative
   one may be repeated. */
static void Compiler._record_objects(Compiler c, List bindings, Token site) {
  foreach (List row, bindings)
    match (row) case %(op = (bind (!set ?binding (binding ? ?)) ?) ?): {
      List key = %(defined $binding);
      if (key in c.semantic_binding_facts())
        c._report_redefinition("variable", binding, site);
      c.set_fact(key, 1);
      c.set_fact(%(arms $binding), c.arms);
    }
}

/* Reports a second definition of one file-scope name, which C rejects,
   when both sit under the same conditional arms. Definitions under
   different arms are not compared. For a variable, whose initializer moves
   into the generated init function, a duplicate under two true conditions
   is therefore not detected, and the later initializer wins. */
static void Compiler._report_redefinition(
  Compiler c, String kind, List binding, Token site) {
  Var arms;
  if (!c.semantic_binding_facts().try_get(%(arms $binding), arms) ||
      !List.equal(arms, c.arms))
    return;
  String spelling = binding_identity_spelling(binding);
  $report.type.decl_duplicate(c, site, kind, spelling);
}

/* A definition remembers the token range of the top-level form that
   produced it, and whether that form is private, for the definition walk.
   A typedef or declaration may repeat its name, so each statement keys its
   own range. */
static void Compiler._record_span(Compiler c, List node, int start, int end) {
  List key = NULL;
  match (node) {
    case %(function ? (bind ?binding ?) ?): key = binding;
    case %(falias (declare ? (bindings (bind ?binding ?))) ?): key = binding;
    case %((!or typedef declare) *): key = node;
  }
  if (key)
    c.set_fact(
      %(definition-span $key), %($start $end ${c.source_private > 0}));
}

/* function completion

   A function's completion fact records its contract: a prototype, a
   definition, a definition that completed a prototype, or a conflict
   between two prototypes. */

// Record only prototypes reached in positioned full-parse source order.
static void Compiler._record_prototypes(
  Compiler c, Type declared_type, List items) {
  foreach (List target, items)
    match (target)
      case %(bind ?binding ?modifiers): {
        List single = %(declare $declared_type (bindings $target));
        Type type = single.type_from_ast();
        if (type.is_function()) c._record_prototype(binding, type, modifiers);
      }
}

static void Compiler._record_prototype(
  Compiler c, List binding, Type type, List modifiers) {
  c._record_attributes(binding, modifiers);
  List contract = c._contract(type, binding);
  Var stored;
  if (c.semantic_binding_facts().try_get(%(completion $binding), stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    if (state_kind == <definition> || state_kind == <completed>) return;
    if (state_kind != <prototype> || !List.equal(prior_contract, contract)) {
      c.set_fact(%(completion $binding), %(conflict));
      return;
    }
  }
  c.set_fact(%(completion $binding), %(prototype $contract));
}

/* A source attribute on the prototype belongs to the function; the
   generator writes it on the prototype it derives from the definition. */
static void Compiler._record_attributes(
  Compiler c, List binding, List modifiers) {
  List attributes = NULL;
  foreach (Var item, modifiers)
    if (item is <list> && car(item) is <string>)
      attributes = attributes ? %( @attributes $item ) : %($item);
  if (attributes)
    c.set_fact(%(attributes $binding), attributes);
}

static void Compiler._record_definition(
  Compiler c, Type type, List binding, Token site) {
  List contract = c._contract(type, binding);
  Var stored;
  if (c.semantic_binding_facts().try_get(%(completion $binding), stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    if (state_kind == <prototype>) {
      c._complete_prototype(binding, prior_contract, contract, site);
      return;
    }
    if (state_kind == <definition> || state_kind == <completed>)
      c._report_redefinition("function", binding, site);
  }
  c.set_fact(%(completion $binding), %(definition $contract));
  c.set_fact(%(arms $binding), c.arms);
  String spelling = binding_identity_spelling(binding);
  if (spelling && !type.is_static()) c.fn_defs[spelling] = 1;
}

/* A definition completes the prior prototype whose contract it matches. A
   definition without `static` after a `static` prototype keeps the
   prototype's internal linkage in C. */
static void Compiler._complete_prototype(
  Compiler c, List binding, List prior_contract, List contract, Token site) {
  match (prior_contract)
    case %(function-contract ?a ?b static ?d)
      if (contract.equal(%(function-contract $a $b extern $d))):
        contract = prior_contract;
  if (!List.equal(prior_contract, contract)) {
    String spelling = binding_identity_spelling(binding);
    $report.type.decl_prototype(c, site, spelling, prior_contract, contract);
  }
  c.set_fact(%(completion $binding), %(completed $contract));
  c.set_fact(%(arms $binding), c.arms);
}

static List Compiler._contract(Compiler c, Type type, List binding) =>
  _completion_contract(
    type, c._fact(%(method $binding)), c._fact(%(self $binding)));

static List _completion_contract(
  Type type, List method_identity, List self_signature) {
  Symbol linkage = type.is_static() ? <static> : <extern>;
  List contract = %(
    function-contract
    ${_contract_type(type, 0)}
    ${_contract_type(type, 1)}
    $linkage
    $method_identity
  );
  return self_signature ? contract.append(%($self_signature)) : contract;
}

static Type _contract_type(Type type, int keep_qualifiers) {
  Array kept = [];
  foreach (Var item, type) {
    if (item is <list>) kept.push(_contract_type(item, keep_qualifiers));
    else if (!_omitted_specifier(item, keep_qualifiers)) kept.push(item);
  }
  return kept.list_free();
}

// A contract omits storage classes, `inline`, and qualifiers unless kept.
static int _omitted_specifier(Var item, int keep_qualifiers) {
  if (item is not <symbol>) return 0;
  Symbol symbol = item;
  return symbol.is_storage_class() ||
         (!keep_qualifiers && symbol.is_type_qualifier()) ||
         symbol.is_inline();
}

// static initializers

static void Compiler._record_static_object(
  Compiler c, Type declared, List bindings) {
  if (!declared.is_static()) return;
  int declared_var = c.sym.is_var_type(declared);
  if (!declared_var && !c._initializable_type(declared)) return;
  foreach (List binding_init, bindings)
    match (binding_init)
      case %(op = (bind (!set ?binding (binding ? ?)) ?)
             (expr (!set ?initializer_type (*)) ?value)): {
        if (declared_var && !c._initializable_type(initializer_type)) continue;
        Map references = {}, Array ordered = [];
        _collect_references(value, references, ordered);
        c.static_init_deps[binding] = ordered.list_free();
      }
}

static int Compiler._initializable_type(Compiler c, Type type) =>
  c.sym.is_string_type(type) || c.sym.is_named_value_type(type, "List") ||
  c.sym.is_array_type(type) || c.sym.is_map_type(type) ||
  c.sym.is_named_value_type(type, "Func");

static void _collect_references(Var value, Map references, Array ordered) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node)
    case %(input *arguments): {
      foreach (List argument, arguments)
        _collect_references(argument.cadr(), references, ordered);
      return;
    }
  match (node)
    case %(indexinit ? ?initializer): {
      _collect_references(initializer, references, ordered);
      return;
    }
  match (node)
    case %(expr (!set ?type (*)) ${$source_identifier_content(
        %((!set ?binding (binding ? ?))))}): {
      if (!type.type().is_function()) {
        if (!references.contains(binding)) ordered.push(binding);
        references[binding] = 1;
      }
      return;
    }
  foreach (Var child, node) _collect_references(child, references, ordered);
}

static void Compiler._check_static_inits(Compiler c) {
  Map statics = c.sym.file_statics();
  foreach (Var (key, value), c.static_init_deps) {
    List binding = key, dependencies = value;
    foreach (List reference, dependencies) {
      String name = binding_identity_spelling(reference);
      if (!name || %($name) in statics) continue;
      String target = binding_identity_spelling(binding);
      $report.parse.static_dependency(c, c._init_token(binding), name, target);
    }
  }
}

static Token Compiler._init_token(Compiler c, List binding) {
  Var index;
  if (!c.init_tokens.try_get(binding, index)) return NULL;
  Token tokens = c.tokenizer.tokens;
  return tokens + index.integer();
}

// meta definitions

/* Emits the runtime form of each imported `meta` function or value this
   unit reaches, in import order. A `meta` declaration has two lifetimes:
   every importing unit installs its compile-time form, and the runtime
   declaration belongs where it is used. A unit that uses one only during
   translation emits nothing for it, and a declaration an emitted one uses
   comes with it. A compile-time-only function has no runtime form to emit,
   so a unit that calls it at run time reaches the link error that names
   it. */
static void Compiler._append_meta_definitions(Compiler c, Array nodes) {
  if (!c.meta_defs.len()) return;
  Map referenced = {}, reached = {};
  foreach (List node, nodes) ast_collect_binding_references(node, referenced);
  /* A `meta` declaration uses only ones declared before it, so one pass
     from the last declaration back reaches every one an emitted one
     needs. */
  for (size_t i = c.meta_defs.len(); i; i--) {
    List definition = c.meta_defs[i - 1];
    Var identity = _meta_identity(definition);
    if (identity in referenced) {
      reached[identity] = 1;
      ast_collect_binding_references(definition, referenced);
    }
  }
  foreach (List definition, c.meta_defs)
    if (_meta_identity(definition) in reached &&
        !c.meta_is_comptime_only(definition)) {
      List emitted = _linked_once(definition);
      c._record_top_level(emitted, NULL);
      nodes.push(emitted);
    }
}

/* Every unit that calls a public `meta` function at run time emits it, and
   units that never include one another cannot tell which of them does, so
   each copy is weak and the program links one. */
static List _linked_once(List definition) {
  match (definition)
    case %(function ?type ?declarator ?body):
      if (!type.type().is_static())
        return %(function ("__attribute__((weak))" @type) $declarator $body);
  return definition;
}

/* The binding an imported `meta` function or declaration introduces. */
static Var _meta_identity(List definition) {
  match (definition) {
    case %(function ? (bind (binding ?identity ?) *) ?): return identity;
    case %(declare ? (bindings (op = (bind (binding ?identity ?) *) ?))):
      return identity;
    case %(declare ? (bindings (bind (binding ?identity ?) *))):
      return identity;
  }
  return void;
}

// tokenizing

/** Scans source and positions the compiler at its first non-trivia token.

    The compiler borrows `text` for diagnostics and macro source capture until
    translation finishes.
*/
void Compiler.tokenize(Compiler c, char *text) {
  if (c._is_script_file()) c.script = c.unit_script;
  c.input_boundary = NULL;
  c.text = text;
  c.tokenizer = Tokenizer.new(c.text, <x2c>);
  c.tokenizer.layout = c.layout || is_layout_file(c.filename);
  c.tokenizer.scan();
  c.layout = c.tokenizer.layout;
  c._report_malformed_token();
  c.scan_conditionals();
  _retag_keywords(c.tokenizer);
  c.token = Token.skip_trivia(c.tokenizer.tokens);
  c.braces.clear();
}

/* The unit's script settings apply to the one file that carries the
   shebang, whichever compiler reads it. */
static int Compiler._is_script_file(Compiler c) =>
  c.unit_script && c.filename &&
  (c.filename == c.unit_script.path ||
   absolute_path(c.filename) == c.unit_script.path);

/* A lexical failure truncates the token stream, so the parser reaches the
   appended `<eof>` and blames the end of the file. Report the refused byte
   instead. An `<incomplete>` token really did run out of source, so it keeps
   the end-of-file diagnostic that describes it. */
static void Compiler._report_malformed_token(Compiler c) {
  Symbol status = c.tokenizer.status();
  if (status != <malformed> && status != <indent>) return;
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <error>) $report.parse.token_malformed(c, token, status);
  }
}

/* `in` and `match` are C identifiers as often as x2c keywords. `in` stays
   the operator where its neighbors plainly end and begin operands, and the
   parser reads it by position everywhere else; `match` is the statement
   only as `match (...)` followed by `case` or `{`. Every other occurrence
   is a name, so C that uses them keeps compiling. */
static void _retag_keywords(Tokenizer tokenizer) {
  Token prev = NULL;
  for (Token token = tokenizer.tokens; token.type != <eof>;
       token = Token.skip_trivia(token + 1)) {
    if (token.type == <in>) {
      Token next = Token.skip_trivia(token + 1);
      if (!(prev && _ends_operand(prev.type) && _starts_operand(next.type)))
        token.type = <ident>;
    }
    else if (token.type == <match>) {
      Token next = Token.skip_trivia(token + 1);
      if (next.type == <(>) next = next.after_group();
      if (next.type != <case> && next.type != <"{">) token.type = <ident>;
    }
    prev = token;
  }
}

static int _ends_operand(Symbol type) {
  switch (type)
    case <ident>: case <lit-int>: case <lit-float>: case <lit-char>:
    case <lit-char*>: case <lit-atom>: case <lit-symbol>: case <)>: case <]>:
      return 1;
  return 0;
}

static int _starts_operand(Symbol type) {
  switch (type)
    case <ident>: case <lit-int>: case <lit-float>: case <lit-char>:
    case <lit-char*>: case <lit-atom>: case <lit-symbol>: case <(>:
    case <"%(">: case <"%[">: case <"%{">: case <"$(">: case <"${">:
    case <$>: case <!>: case <->: case <*>: case <&>: case <~>: case <++>:
    case <-->:
      return 1;
  return 0;
}

// token navigation

/** Returns the non-trivia token type `steps` from parser position.

    Zero reads the current token; positive and negative steps count forward
    and backward through non-trivia tokens. The parser cursor is unchanged.
*/
Symbol Compiler.peek(Compiler c, int steps) {
  Token token = c.token;
  if (!steps && c.at_completion()) {
    List rows = c.sym.visible_symbols();
    raise %(replcomp (kind <names>) (rows $rows) (keywords ()));
  }
  while (steps > 0) {
    token = Token.skip_trivia(token + 1);
    steps--;
  }
  while (steps < 0) {
    token = _skip_backward(token - 1, c.tokenizer.tokens);
    steps++;
  }
  return token.type;
}

/** Returns the first token at or after `token` that is not a space,
    comment, or preprocessor line. The stream must end in `eof`.
*/
Token Token.skip_trivia(Token token) {
  if (token.type == <eof>) return token;
  loop {
    switch (token.type) {
      case <space>: case <comment>: case <preproc>: token++; break;
      default: return token;
    }
  }
}

static Token _skip_backward(Token token, Token origin) {
  while (token > origin) {
    switch (token.type) {
      case <space>: case <comment>: case <preproc>: token--; break;
      default: return token;
    }
  }
  return origin;
}

/** Raises `<incomplete>` when a required grammar item reaches the supplied
    input boundary. The caller sets a token in the current token stream after
    tokenizing; tokenization clears it. Semantic failures do not call this.
*/
void Compiler.require_input(Compiler c) {
  if (c.input_boundary && c.token >= c.input_boundary) raise %(incomplete);
}

/** Requires and consumes the current token type.

    A mismatch reports a parse diagnostic. An active recovery boundary raises
    `<malformed>`; without one, diagnostic reporting exits.
*/
Symbol Compiler.expect(Compiler c, Symbol type) {
  if (c.token.type != type) {
    c.require_input();
    $report.parse.token_expected(c, type);
  }
  c.next();
  return type;
}

/** Consumes the current token and advances past following trivia.

    This updates the unmatched-brace stack. An unmatched `}` reports a parse
    diagnostic, which raises `<malformed>` under recovery and otherwise exits.
*/
void Compiler.next(Compiler c) {
  Token consumed = c.token;
  if (consumed.type == <eof>) return;
  c.token = Token.skip_trivia(consumed + 1);
  c._update_brace_stack(consumed);
}

static void Compiler._update_brace_stack(Compiler c, Token consumed) {
  if (!consumed) return;
  switch (consumed.type) {
    case <"{">: case <"%{">: case <"${">: case <"@{">:
      c.braces.push(consumed);
      break;
    case <"}">:
      if (c.braces.len()) c.braces.take_last();
      else {
        $report.parse.brace_unexpected(c, consumed);
      }
      break;
  }
}

/** Consumes `type` when current and reports whether it matched. */
inline int Compiler.test(Compiler c, Symbol type) {
  if (c.token.type != type) return 0;
  c.next();
  return 1;
}

/** Reports whether the current token is the identifier `word`. A contextual
    keyword such as `with` or `as` is an ordinary identifier elsewhere. This
    query does not consume tokens. */
int Compiler.at_word(Compiler c, String word) =>
  c.peek(0) == <ident> && c.token.text == word;

/** Consumes the identifier `word` when current and reports whether it
    matched. */
int Compiler.take_word(Compiler c, String word) {
  if (!c.at_word(word)) return 0;
  c.next();
  return 1;
}

static void Compiler._check_unmatched_braces(Compiler c) {
  if (!c.braces.len()) return;
  $report.parse.brace_missing(c, c.braces[-1]);
}

/** Returns 1 for a token type that opens a delimited group, -1 for one that
    closes a group, and 0 otherwise. Every opener spelling ends in the `(`,
    `[`, or `{` that its closer matches.
*/
int Symbol.group_step(Symbol s) {
  switch (s) {
    case <"(">: case <"[">: case <"{">: case <"?(">: case <"$(">:
    case <"${">: case <"%(">: case <"%[">: case <"%{">: case <"@{">:
      return 1;
    case <")">: case <"]">: case <"}">:
      return -1;
  }
  return 0;
}

/** Returns the token that closes the group `t` opens, `t` itself when it
    opens no group, or the `eof` token when the group never closes.
*/
Token Token.group_close(Token t) {
  for (int depth = 0; t.type != <eof>; t++)
    if ((depth += t.type.group_step()) <= 0) return t;
  return t;
}

/** Returns the first non-trivia token after the group `t` opens, or after
    `t` when it opens no group. A group that never closes yields `eof`.
*/
Token Token.after_group(Token t) {
  t = t.group_close();
  return t.type == <eof> ? t : Token.skip_trivia(t + 1);
}

// completion

/** Retags the token beginning at `position` as a private completion marker. */
void Compiler.mark_completion(Compiler c, int position) {
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.pos == position && token.type == <ident>) {
      token.type = <replcomp>;
      return;
    }
  }
}

/** Reports whether the parser is at the private REPL completion marker. */
int Compiler.at_completion(Compiler c) => c.token.type == <replcomp>;

/* Transfers completion from the grammar production that owns the cursor.
   Rows retain semantic namespace facts; keywords are choices owned by that
   production rather than an editor-side copy of the grammar. */
void Compiler.__complete_here(Compiler c, Symbol role, List keywords) {
  if (!c.at_completion()) return;
  List rows = c.sym.visible_symbols();
  raise %(replcomp (kind $role) (rows $rows) (keywords $keywords));
}

/* source locations

   An origin row locates a parsed node for later diagnostics. With source
   facts on, as for the editor adapter, declarations and references also
   record their source ranges. */

/** Records a token's location and returns its one-based occurrence.

    A null token returns zero. Callers pass the token that opened a construct,
    so an `(at N node)` wrapper retains its start for transform diagnostics
    after `c.token` has reached end of file.
*/
int Compiler.record_origin(Compiler c, Token token) {
  if (!token) return 0;
  String file = c.filename ? c.filename : "<stdin>";
  if (!c.source_map) file = c.display_path(file);
  c.origins.push(
    %(source $file ${token.line} ${token.col} ${token.len} ${token.pos}));
  return c.origins.len();
}

/** Wraps a parsed node in the source location of its opening token.

    A null node remains null. Macro construction uses its active `m-origin`
    marker; otherwise a node without a token remains unwrapped.
*/
List Compiler.anchor_origin(Compiler c, List node, Token token) {
  if (!node) return node;
  if (c.macro_holes) return %(at m-origin $node);
  int occurrence = c.record_origin(token);
  if (!occurrence) return node;
  return %(at $occurrence $node);
}

/** Records a physical declaration using the binding's actual scope and key. */
void Compiler.record_source_declaration(
  Compiler c, List binding, Token first, Token after) {
  if (!c.source_facts || c.macro_holes) return;
  Var value;
  if (!c.semantic_binding_facts().try_get(%(src-key $binding), value)) return;
  List source_key = value, range = c._source_range(first, after);
  if (!range) return;
  Map symbols = source_key.car();
  List key = source_key.cadr();
  Type type = symbols[key];
  List declaration = %(@range $type);
  c.sym.put(c.source_declarations, source_key, declaration);
  if (c.source_primary && !c.shallow) {
    c.source_definitions[binding] = declaration;
    c.source_occurrences.push(%(@range $binding $type));
  }
}

static List Compiler._source_range(Compiler c, Token first, Token after) {
  if (!first || !after || first >= after || c.macro_holes) return NULL;
  Token last = after - 1;
  while (last > first &&
         (last.type == <space> || last.type == <comment> ||
          last.type == <preproc>)) last--;
  String path = absolute_path(c.filename);
  if (!c.source_texts.contains(path)) c.source_texts[path] = c.text;
  return %($path ${first.pos} ${last.pos + last.len});
}

/** Records a resolved reference without inventing spans for constructed
    ASTs.
*/
void Compiler.record_source_reference(
  Compiler c, List binding, Type type, Token first, Token after) {
  if (!c.source_facts || !c.source_primary || c.shallow || c.macro_holes ||
      !binding_identity_try_parts(binding, NULL, NULL)) return;
  List range = c._source_range(first, after);
  if (range) c.source_occurrences.push(%(@range $binding $type));
}

/** Carries declaration metadata with one actual symbol contribution. */
void Compiler.copy_source_declaration(
  Compiler c, Map target, Map source, List key) {
  if (!c.source_facts) return;
  Var declaration;
  List target_key = %($target $key);
  if (c.source_declarations.try_get(%($source $key), declaration))
    c.sym.put(c.source_declarations, target_key, declaration);
  else c.sym.drop(c.source_declarations, target_key);
}

/** Carries declaration metadata beside a completed symbol-map merge. */
void Compiler.merge_source_declarations(Compiler c, Map target, Map source) {
  if (!c.source_facts) return;
  foreach (Var key, source.keys())
    if (key is <list>) c.copy_source_declaration(target, source, key);
}

/* binding facts

   Facts about bindings share one map, keyed by rows such as
   `(emitted BINDING)` and `(completion BINDING)`. */

/** Returns a binding's selected emitted spelling.

    A binding without an explicit emission rename uses its identity spelling.
*/
String Compiler.emitted_binding_name(Compiler c, List binding) {
  Var renamed;
  Map facts = c.semantic_binding_facts();
  if (facts.try_get(%(emitted $binding), renamed)) return renamed;
  return binding_identity_spelling(binding);
}

// The List a binding fact holds, or NULL when the fact is absent.
static List Compiler._fact(Compiler c, List key) {
  Var stored;
  return c.semantic_binding_facts().try_get(key, stored) ? stored : NULL;
}

/** Returns the optional references proven present in this lexical path. */
List Compiler.present_references(Compiler c) =>
  c._fact(%(present-references));

/** Records a nonnull optional parameter for the current lexical path. */
void Compiler.mark_reference_present(Compiler c, List binding) {
  List present = c.present_references();
  if (!(binding in present))
    c.set_fact(%(present-references), cons(binding, present));
}

/** Marks the optional reference `binding` present after an `if` when the
    arm that runs without it cannot fall through: `no` when the true arm
    proves presence, `yes` otherwise. A missing `no` arm falls through. */
void Compiler.settle_reference(
  Compiler c, List binding, int true_is_present, List yes, List no) {
  if (binding && reference_guard_exits(true_is_present ? no : yes))
    c.mark_reference_present(binding);
}

/** Restores the optional-reference facts saved before a lexical path. */
void Compiler.restore_reference_presence(Compiler c, List before) {
  if (before === c.present_references()) return;
  if (before) c.set_fact(%(present-references), before);
  else c.drop_fact(%(present-references));
}

/** Returns the optional-reference parameter tested by `condition`, or NULL.
    `truth` is set to whether the condition's true arm proves that the caller
    supplied an object. Only a direct truth or null test proves presence.
*/
List Compiler.optional_reference_test(
  Compiler c, List condition, int &truth) {
  match (condition) {
    case %(expr ? ${$grouped(?inner)}):
      return c.optional_reference_test(inner, truth);
    case %(expr ? ${$source_operator_content(%(! ?operand))}): {
      truth = !truth;
      return c.optional_reference_test(operand, truth);
    }
    case %(expr ? ${$source_operator_content(
        %((!set ?op (!or == !=)) ?left ?right))}):
      return c._null_comparison(op, left, right, truth);
    case %(expr (opt-ref *) ${$source_identifier_content(%(?binding))}):
      if (%(optional-reference-param $binding) in
          c.semantic_binding_facts()) return binding;
  }
  return NULL;
}

/* A comparison with a null literal tests the other operand; its true arm
   proves presence for `!=`. */
static List Compiler._null_comparison(
  Compiler c, Var op, Var left, Var right, int &truth) {
  if (_null_literal(right)) {
    truth = op == <!=>;
    return c.optional_reference_test(left, truth);
  }
  if (!_null_literal(left)) return NULL;
  truth = op == <!=>;
  return c.optional_reference_test(right, truth);
}

static int _null_literal(List expr) {
  match (expr) {
    case %(expr ? ${$grouped(?inner)}):
      return _null_literal(inner);
    case %(expr ? ${$source_identifier_content(
        %((binding ? "NULL")))}): return 1;
    case %(expr ? ${$source_literal_content(%(? "0"))}): return 1;
  }
  return 0;
}

/** Returns whether `arm` ends with a return or non-returning raise. */
int reference_guard_exits(List arm) {
  if (Ast.never_returns(arm)) return 1;
  match (arm) {
    case $source_return_content(%(*)): return 1;
    case %(at ? ?body): return reference_guard_exits(body);
    case $source_block_content(%(*items)):
      return items && reference_guard_exits(items.last());
  }
  return 0;
}

// generated names and initializers

/** Allocates the next compiler-private C spelling for `stem`.

    Related compilers increment the same per-stem counter, except while a
    macro import is being parsed, which counts separately. An import's `meta`
    bodies are parsed in every unit that imports the file and in none that is
    built from the `.xi` prelude, so a name minted there must not move the
    unit's own counter or the two modes emit different C. Those names carry
    an `m` before the stem, so they cannot collide with the unit's.
*/
String Compiler.fresh_name(Compiler c, String stem) {
  String key = c.import_src ? %"m$stem" : stem;
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  String name = %"_x2c_${key}_${count++}";
  c.names.counters[key] = count;
  return name;
}

/** Returns a fresh semantic identity for an anonymous aggregate.
    Identities are scoped to the compiler's current file and numbered per
    file, so every process mints the same sequence for one file and two
    files never share an identity. No emission path prints one.
*/
List Compiler.gensym(Compiler c) {
  String owner = c.filename
    ? home_portable_path(c.canonical_path(c.filename)) : "";
  String key = %"gensym:$owner";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored.int() + 1 : 1;
  c.names.counters[key] = count;
  return %((gensym $owner $count));
}

/** Appends a generated declaration to the early-declaration queue. */
void Compiler.add_early(Compiler c, List decl) {
  c.early_decls.push(decl);
}

/** Appends a statement to file initialization order under `phase`, which is
    `<protocol>` for protocol setup, or `<early>`, `<mid>`, or `<late>` for
    the file initializer's three stages. Generation splices the statement
    after the transform has run, so it must already be lowered: bound code
    that still needs lowering, such as a `String` literal, reaches C as is.
*/
void Compiler.add_init(Compiler c, Symbol phase, List stmt) {
  c.inits.push(%($phase $stmt));
}

// the literal cache

/** Interns a constant key and returns its stable `(cache id)` reference. */
List Compiler.cache(Compiler c, List key) {
  List alias = _cache_alias(key);
  if (alias) return alias;
  int nextid = c.id_keys.len(), id = c.key_ids.setdefault(key, nextid);
  if (id == nextid) c.id_keys.push(key);
  return %(cache $id);
}

static List _cache_alias(List key) {
  match (key) {
    case %(cache ?):                          return key;
    case %(expr ? (cache ?id)):               return %(cache $id);
    case %(var (expr ("Var") (cache ?id))):   return %(cache $id);
    case %(expr ("List") (cache ?id)):        return %(cache $id);
  }
  return NULL;
}

/** Caches a cons cell when both parts have immutable cache forms.

    Returns `NULL` when runtime literals are required or either part cannot
    be represented by the immutable cache graph.
*/
List Compiler.cache_cons_cell(Compiler c, List head, List tail) {
  if (c.runtime_literals) return NULL;
  List head_cache = NULL, tail_cache = NULL;
  if (head.match(%(expr ("Var") (cache *)))) head_cache = head.caddr();
  else if (head.match(%(cache *))) head_cache = head;
  if (!head_cache) return NULL;
  if (tail.match(%(expr ("List") (cache *)))) tail_cache = tail.caddr();
  else if (tail.match(%(nil))) tail_cache = tail;
  if (!tail_cache) return NULL;
  List cached = c.cache(%(cons $head_cache $tail_cache));
  return %(expr ("List") $cached);
}

/** Interns an immutable value and returns its `(cache id)` reference.
    `value` is a `List` of such values, a `String`, a number with its tag, or
    a `Symbol`; any other value returns NULL.
*/
List Compiler.cache_literal_var(Compiler c, Var value) {
  if (value is <list>) {
    List cached = c._cache_literal_list(value);
    return c.cache(%( var (expr ("List") (expr ("List") $cached)) ));
  }
  if (value is <string>) {
    List literal = %(expr ("String") (literal ("String") $value));
    List cached = c.cache(%(string $literal));
    return c.cache(%(var (expr ("String") $cached)));
  }
  if (value.is_integer() || value.is_floating())
    return c._cache_boxed(c.meta_value_expression(NULL, value, NULL));
  if (value is <lsym>)
    return c._cache_boxed(
      %(expr ("Atom") (literal ("Atom") ${value.str()} $value)));
  if (value is not <symbol>) return NULL;
  String spelling = value.symbol();
  List literal = %(
    expr ("Symbol") (literal ("Symbol") $spelling $value)
  );
  return c.cache(%(var $literal));
}

// A number or atom is cached through its conversion to a `Var`.
static List Compiler._cache_boxed(Compiler c, List literal) {
  literal = c.convert_expression(literal, %("Var"));
  return c.cache(%(var $literal));
}

static List Compiler._cache_literal_list(Compiler c, List values) {
  Array heads = $auto([]);
  foreach (Var value, values) heads.push(c.cache_literal_var(value));
  List cached = %(nil);
  for (int i = (int) heads.len() - 1; i >= 0; i--) {
    List head = heads[i];
    cached = c.cache(%(cons $head $cached));
  }
  return cached;
}

/** Returns a runtime `List` expression for cached compiler-owned syntax.

    `values` may contain nested `List`s, `String`s, integer `Var`s, and
    `Symbol`s.
*/
List Compiler.cache_literal_list(Compiler c, List values) {
  List cached = c._cache_literal_list(values);
  return %(expr ("List") (expr ("List") $cached));
}

/* match pattern values

   The compile-time value graph behind a Match pattern represents dynamic
   expressions by a private marker, so binder analysis can distinguish a
   computed operator head from ordinary literal data. */

/** Recovers a pattern value graph, using `x2c-dyn` for computed values. */
Var Compiler.match_pattern_value(Compiler c, Var node) {
  if (node is not <list>) return node;
  List ast = node;
  if (!ast) return %();
  Var (head, second, third) = ast;
  if (head == <cache>) return c.match_pattern_value(c.id_keys[second]);
  if (head == <expr>) {
    match (ast) case %(expr ("Var") (call ? (args ?argument))):
      if (c.is_builtin_converter_call(ast))
        return c.match_pattern_value(argument);
    return c.match_pattern_value(ast.last());
  }
  if (head == <var>) return c.match_pattern_value(second);
  if (head == <string>) return c.match_pattern_value(second);
  if (head == <call>) return c._call_value(second, third);
  if (head == <literal>) return ast.last();
  if (head == <nil>) return %();
  if (head == <cons>) return c._cons_value(second, third);
  return <x2c-dyn>;
}

/* A case pattern matches what its labels match. Other untyped calls are
   computed; typed builtin boxers were recognized with their expression. */
static Var Compiler._call_value(Compiler c, Var callee, Var args) {
  String converter = _converter_name(callee);
  if (converter == "Macro_case_pattern")
    match (args) case %(args ? ?names): {
      List labels = c.match_pattern_value(names);
      return %(!and x2c-dyn @labels);
    }
  return <x2c-dyn>;
}

static Var Compiler._cons_value(Compiler c, Var head, Var tail) {
  Var value = c.match_pattern_value(head);
  Var rest = c.match_pattern_value(tail);
  if (rest is not <list>) return <x2c-dyn>;
  return cons(value, rest);
}

static String _converter_name(Var node) {
  if (node is <string>) return node;
  match (node)
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      return binding_identity_spelling(binding);
  return NULL;
}

/** Reports whether a recovered pattern value graph is fully static. */
int match_value_is_static(Var value) {
  if (value == <x2c-dyn>) return 0;
  if (value is not <list>) return 1;
  foreach (Var part, value.list()) if (!match_value_is_static(part)) return 0;
  return 1;
}

/** Reports whether a typed `Match` pattern has a fully static value graph. */
int Compiler.match_pattern_is_static(Compiler c, List pattern) =>
  match_value_is_static(c.match_pattern_value(pattern));

/** Returns a recovered pattern value's fixed literal head symbol, or zero.

    A binder, guard, non-list value, or computed head has no fixed symbol.
    Other pattern elements may remain dynamic because a literal head alone
    constrains the first input element.
*/
Symbol match_value_head(Var value) {
  if (value is not <list>) return 0;
  Var head = car(value);
  if (head is not <symbol> || head == <x2c-dyn> ||
      head.is_binder() || head.is_match_op())
    return 0;
  return head;
}

/** Returns the head of a flat Symbol-and-captures pattern value, or zero.

    Each element after the head is a unique named `?` binder or a typed
    capture of one. When `tags` is non-null, stores one entry per binder
    in order: the capture's tag Symbol, or integer zero when untyped.
*/
Symbol match_value_flat_head(Var value, List binders, List &?tags) {
  Symbol head = match_value_head(value);
  if (!head) return 0;
  List elements = value.list().cdr();
  Array typed = $auto([]);
  for (List cursor = binders; cursor && elements;
       cursor = cursor.cdr(), elements = elements.cdr()) {
    Var binder = cursor.car(), element = elements.car();
    Symbol tag = 0;
    if (!binder.is_atom_binder() || binder == <?>) return 0;
    if (element != binder && !(tag = _flat_capture_tag(element, binder)))
      return 0;
    typed.push(tag ? (Var) tag : (Var) 0);
  }
  if (binders.len() != typed.len() || elements) return 0;
  if (tags) tags = typed;
  return head;
}

/* A typed capture element is `(!is ?name type <tag>)` with a literal tag.
   The runtime matcher canonicalizes `varray` and `vmap`; those spellings
   keep the runtime path rather than repeating that rule here. */
static Symbol _flat_capture_tag(Var element, Var binder) {
  match (element)
    case %((!quote !is) ?name type ?(Symbol tag)):
      if (name == binder && tag != <x2c-dyn> &&
          tag != <varray> && tag != <vmap>) return tag;
  return 0;
}

/* match binders

   A pattern's definite binders become declarations in the scope of its
   case, or of its catch clause, whose lowering keeps the issued bindings. */

/** Returns definite binders from a typed `Match` pattern AST.

    When `possible` is non-null, stores every binder appearing on any path.
*/
List Compiler.match_pattern_binders(
  Compiler c, List pattern, List &?possible) {
  Var value = c.match_pattern_value(pattern);
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(value);
  List definite = layout.definite_list();
  if (possible) possible = layout.possible_list();
  layout.free();
  return definite;
}

/** Defines a typed `Match` pattern's definite binders in the current scope. */
void Compiler.define_match_binders(Compiler c, List pattern) {
  foreach (Var binder, c.match_pattern_binders(pattern, NULL)) {
    String name = binder.str()[1:];
    c.sym.define(%($name), _binder_type(binder));
  }
}

/** Defines catch binders and returns their capture-token/binding pairs. */
List Compiler.define_catch_binders(Compiler c, List pattern) {
  Array rows = [];
  foreach (Var binder, c.match_pattern_binders(pattern, NULL)) {
    String name = binder.str()[1:];
    List binding = c.sym.declare(NULL, %($name), _binder_type(binder));
    rows.push(%($binder $binding));
  }
  return rows.list_free();
}

static List _binder_type(Var binder) =>
  binder.is_list_binder() ? %("List") : %("Var");

/** Builds ordinary declarations from a catch scope's issued bindings. */
List Compiler.catch_binder_declarations(
  Compiler c, List bindings, List handle) {
  Array declarations = [];
  int index = 0;
  foreach (List row, bindings) {
    Type type = _binder_type(row.car());
    List value = %(expr ("Var")
      (call "x2c_error_catch_capture"
        (args (expr ("ErrorHandler") (ident $handle))
              (expr (int) (literal (int) ${%"${index++}"})))));
    if (row.car().is_list_binder())
      value = %(expr $type (call "Var_list" (args $value)));
    declarations.push(%(declare $type (bindings (bind ${row.cadr()} ()))));
    declarations.push(
      %(stmnt (expr $type (op = (expr $type (ident ${row.cadr()})) $value))));
  }
  return declarations.list_free();
}

/* diagnostics routing

   A child compiler either shares its owner's diagnostic store or keeps its
   own, whose reports the owner takes when the child closes. */

/** Routes this compiler's diagnostic store through its own printer.

    Compilers that share a store call this when taking the diagnostic stream
    back from another compiler.
*/
void Compiler.own_diagnostics(Compiler c) {
  c.diagnostics.printer = c;
}

/** Shares a caller's diagnostic stream while preserving its emission policy.
    The caller restores the saved printer after this child finishes.
*/
void Compiler.borrow_diagnostics(Compiler c, Compiler owner) {
  c.diagnostics = owner.diagnostics;
  if (c.diagnostics.printer) c.own_diagnostics();
}

/** Retains a child's final diagnostics and closes its owned Lisp session. */
void Compiler.close_child(Compiler c, Compiler child) {
  c.take_diagnostics(child);
  child.free_lisp();
}

// related compilers

/** Shares the symbol table, literal cache, and protocol registries of the
    unit `owner` is translating, so a child that binds declarations binds
    them into that unit. A `meta` definition in a macro import is bound here
    and emitted by `owner`, so both compilers must read one table: its
    `(cache id)` references index `owner`'s keys, and its operations resolve
    through `owner`'s protocol rows. Both install into one macro session, so
    they also read one record of which `meta` functions reach file-scope
    state.
*/
void Compiler.borrow_unit_semantics(Compiler c, Compiler owner) {
  c.sym = owner.sym;
  c.fn_defs = owner.fn_defs;
  c.id_keys = owner.id_keys;
  c.key_ids = owner.key_ids;
  c.protocols = owner.protocols;
  c.adoptions = owner.adoptions;
  c.conforms = owner.conforms;
  c.protocol_helpers = owner.protocol_helpers;
  c.proto_cache = owner.proto_cache;
  c.meta_comptime = owner.meta_comptime;
  c.meta_regions = owner.meta_regions;
  c.meta_hashes = owner.meta_hashes;
  c.meta_calls = owner.meta_calls;
  c.native_meta = owner.native_meta;
}

/** Shares `owner`'s pending `meta` group and the definitions it reads, which
    belong with the Lisp session that holds the group's stubs. */
void Compiler.share_meta_group(Compiler c, Compiler owner) {
  c.meta_group = owner.meta_group;
  c.meta_group_bound = owner.meta_group_bound;
  c.meta_defs = owner.meta_defs;
}

/** Takes over `owner`'s macro, object-like `#define`, import, keyword,
    literal cache, and Lisp state for one segment of a collected file.
    Segments are one translation unit, so retained macro bodies index the
    unit's literal cache and use its Lisp environment.
*/
void Compiler.take_unit_state(Compiler c, Compiler owner) {
  c.id_keys = owner.id_keys;
  c.key_ids = owner.key_ids;
  c.macros = owner.macros;
  c.object_macros = owner.object_macros;
  c.imports = owner.imports;
  c.kw_aliases = owner.kw_aliases;
  c.kw_seen = owner.kw_seen;
  c.macro_lisp = owner.macro_lisp;
  c.declaration_effects = owner.declaration_effects;
  c.borrowed_lisp = c.macro_lisp != NULL;
  c.share_meta_group(owner);
}

/** Returns that state to `owner`, so the next segment starts where this one
    finished and any Lisp environment this segment created stays alive after
    the shadow is released.
*/
void Compiler.return_unit_state(Compiler c, Compiler owner) {
  owner.macros = c.macros;
  owner.object_macros = c.object_macros;
  owner.imports = c.imports;
  owner.kw_aliases = c.kw_aliases;
  owner.kw_seen = c.kw_seen;
  owner.macro_lisp = c.macro_lisp;
  owner.declaration_effects = c.declaration_effects;
  owner.declaration_produced |= c.declaration_produced;
  c.borrowed_lisp = c.macro_lisp != NULL;
}

// source files and dependencies

/** Reads a source through the request view and retains exact response
    bytes.
*/
int Compiler.read_source(Compiler c, String path, String volatile &text) {
  if (!c.sources.read(path, text)) return 0;
  if (c.source_facts) c.source_texts[Path.absolute(path)] = text;
  return 1;
}

/** Returns the spelling that identifies the file at `path`. Through a
    source view it is the absolute path, because an unsaved file need not
    exist on disk; otherwise it is the real path, or `path` itself when that
    does not resolve.
*/
String Compiler.canonical_path(Compiler c, String path) {
  if (c.sources) return Path.absolute(path);
  String real = real_path(path);
  return real ? real : path;
}

/* The real paths this process has resolved, by spelling. The compiler
   never changes its working directory, and translation workers are forked
   processes, so a spelling keeps its answer. A spelling that does not
   resolve is asked again, because its file may appear later. */
static Map real_paths = NULL, static Scope real_paths_scope = NULL;

/** Returns the real path of the existing file at `path`, or NULL when
    `path` is NULL or does not resolve. Each spelling is resolved once per
    process.
*/
String real_path(String path) {
  if (!path) return NULL;
  Var known = _real_paths()[path];
  if (known is <string>) return known;
  char resolved[PATH_MAX];
  if (!realpath(path, resolved)) return NULL;
  String real = resolved;
  if (path.try_own() && real.try_own()) real_paths[path] = real;
  return real;
}

/** Returns `Path.absolute(path)`, resolving an existing file through
    `real_path`. */
String absolute_path(String path) {
  String real = real_path(path);
  return real ? real : Path.absolute(path);
}

static Map _real_paths(void) {
  if (real_paths != NULL) return real_paths;
  $scope(&real_paths_scope) {
    Scope.shutdown_hook(_real_paths_shutdown);
    real_paths = {};
  }
  return real_paths;
}

static void _real_paths_shutdown(void) {
  real_paths_scope.destroy();
  real_paths_scope = NULL;
  real_paths = NULL;
}

/** Returns `path` relative to the canonical x2c home when it lies below the
    home, otherwise `path`. Interfaces, macro definitions, retained
    declarations, and generated identities spell paths this way, so they do
    not depend on where the home is installed.
*/
String home_portable_path(String path) {
  String prefix = %"${x2c_get_root()}/";
  return path.startswith(prefix) ? path[prefix.len():] : path;
}

/** Returns the absolute path that a `home_portable_path` spelling names. */
String home_absolute_path(String spelling) =>
  spelling.startswith("/") ? spelling : %"${x2c_get_root()}/$spelling";

/** Merges one translation dependency, preserving an existing content hash. */
void Map.merge_translation_dependency(Map m, String path, Var content_hash) {
  if (content_hash is <string>) {
    if (m[path] is not <string>) m[path] = content_hash;
  }
  else m.setdefault(path, 1);
}

/** Records a path dependency not embedded in generated C. */
void Compiler.add_translation_dependency(Compiler c, String path) {
  c.deps.merge_translation_dependency(path, 1);
}

/** Merges another translation's dependency rows into this compiler. */
void Compiler.merge_translation_dependencies(Compiler c, Map dependencies) {
  foreach (Var (path, content_hash), dependencies)
    c.deps.merge_translation_dependency(path, content_hash);
}

// translation state and lifecycle

/** Creates a compiler with independent package and generated-name state. */
Compiler Compiler.new(void) => _new(NULL);

/** Creates a compiler sharing its owner's package and generated-name state. */
Compiler Compiler.new_shared(Compiler owner) {
  /* Shallow collection compilers must declare into the same package space,
     and share the owner's package maps so an import seen in one segment is
     registered and collected exactly once for the whole unit. */
  return _new(owner);
}

// Zero finalizer-visible state before any fallible initialization.
static Compiler _new(Compiler owner) {
  Compiler c =
    Scope.malloc_finalized(sizeof(struct Compiler), _drop_compiler);
  memset(c, 0, sizeof(struct Compiler));
  c._init_tables();
  if (owner) c._share_unit(owner);
  else c._own_unit();
  c.sym = Sym.new(c);
  c._init_queues();
  c.collect_protocols = 1;
  c.diagnostics = Diagnostics.new(
    owner && owner.diagnostics.printer ? c : NULL,
    owner ? owner.diagnostics.limit : 1);
  c.braces = [];
  c.line_starts = [];
  c.import_stack = [];
  c.origins = [];
  c.root_dir = x2c_get_root();
  return c;
}

static void Compiler._init_tables(Compiler c) {
  c.id_keys = [];
  c.key_ids = {};
  c.deps = {};
  c.macros = {};
  c.kw_aliases = {};
  c.kw_seen = {};
  c.object_macros = {};
  c.proto_cache = {};
  c.imports = {};
  c.init_tokens = {};
  c.static_init_deps = {};
  c.fn_defs = {};
  c.meta_comptime = {};
  c.meta_regions = {};
  c.meta_hashes = {};
  c.meta_calls = {};
  c.native_meta = {};
}

/* A child compiler owns its tokens, symbols, and diagnostics. Package
   registries and generated-name state belong to the whole translation
   unit, so every child must mutate the owner's exact objects. */
static void Compiler._share_unit(Compiler c, Compiler owner) {
  c.package = owner.package;
  c.package_dirs = owner.package_dirs;
  c.package_roots = owner.package_roots;
  c.package_aliases = owner.package_aliases;
  c.package_members = owner.package_members;
  c.package_exports = owner.package_exports;
  c.names = owner.names;
  c.source_map = owner.source_map;
  c.recovery_depth = owner.recovery_depth;
  c.sources = owner.sources;
  c.declaration_produced = owner.declaration_produced;
  c.source_facts = owner.source_facts;
  c.source_occurrences = owner.source_occurrences;
  c.source_definitions = owner.source_definitions;
  c.source_declarations = owner.source_declarations;
  c.source_texts = owner.source_texts;
  c.unit_script = owner.unit_script;
  c.include_dirs = owner.include_dirs;
  c.meta_build = owner.meta_build;
}

/* The first compiler of a unit creates the state its children share and
   starts from the shared session's compile-time-only definitions. */
static void Compiler._own_unit(Compiler c) {
  c.inherit_library_comptime();
  c.package_roots = {};
  c.package_aliases = {};
  c.package_members = {};
  c.package_exports = {};
  c.names = Scope.calloc(1, sizeof(struct GenNames));
  c.names.counters = {};
  c.names.adapters = {};
  c.names.file_scope_owners = {};
}

static void Compiler._init_queues(Compiler c) {
  c.inits = [];
  c.early_decls = [];
  c.meta_defs = [];
  c.meta_group = [];
  c.meta_group_bound = {};
}

/** Destroys a compiler's owned `Lisp` session, if any.

    A borrowed session is left alive. Owned sessions not freed here are
    destroyed when the compiler's Scope ends. This is final compiler cleanup:
    it clears the diagnostic store and the compiler must not be reused.
    At process exit, root Scope cleanup follows shutdown hooks and canonical
    pool cleanup. Close explicitly while any native session dependencies live.
*/
void Compiler.free_lisp(Compiler c) {
  if (!c) return;
  if (c.macro_lisp && !c.borrowed_lisp) {
    c.macro_lisp.destroy();
    c.macro_lisp = NULL;
  }
  c.diagnostics = NULL;
}

// Lisp calls must have returned before the compiler's Scope is reclaimed.
static void _drop_compiler(void *ptr) {
  Compiler c = ptr;
  c.free_lisp();
}
