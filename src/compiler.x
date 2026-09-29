/*  compiler.x -- core x2c compiler state and operations

    Copyright (c) 2025 Gary William Flake.

    Coordinates tokenization, shallow declaration discovery, full parsing,
    symbol scopes, diagnostics, and generated initialization. Shallow parsing
    skips function bodies; full parsing produces the AST of the source.

    `Symbol` lookup walks the scope stack from inner to outer. Diagnostics may
    exit immediately or raise `<malformed>` while a recovery boundary is
    active.
  */
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "tokenizer.x"
#include "ast.x"
#include "type.x"
#include "logger.x"
#include "sourceview.x"

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
/** Names a scope-owned, one-use semantic transaction. */
typedef struct SymTxn *SymTxn;

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
     spelling alias -> package name, and package_members each `with` local
     spelling -> (package member). */
  String package, List package_dirs;
  Map package_roots, package_aliases, package_members;
  Token token;
  // Optional end of supplied input; NULL keeps ordinary file diagnostics.
  Token input_boundary;
  Tokenizer tokenizer;
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
     share. `meta_calls` lists the names each `meta` definition references. */
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
  /* A macro import whose protocol registries are installed on first use;
     `Compiler.protocol_members_for` owns the installation. */
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

#include "diagnostics.x"

/* Lambda captures store non-reference values as Var, so traversal callbacks
   that carry the compiler need this raw pointer crossing. The pointee and its
   lifetime stay with the caller. */
/** Boxes the compiler's pointer; the caller keeps the compiler. */
Var Compiler.var(Compiler compiler) => (Var) { .p64 = compiler };

/** Recovers the compiler pointer boxed by `Compiler.var`. */
Compiler Var.compiler(Var value) => value.p64;

protocol Var(Compiler) as void *;
#pragma private

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

// translation state and lifecycle

typedef struct Sym {
  Block scopes, Map globals, statics, binding_facts;
  int base_scopes, local_macro_names;
  // Owning compiler, so type resolution can report its own diagnostics.
  Compiler compiler;
} *Sym;

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
  c.sym = _new_sym(c);
  c._init_queues();
  c.collect_protocols = 1;
  c.diagnostics = Diagnostics.new(
    owner && owner.diagnostics.printer ? c : NULL,
    owner ? owner.diagnostics.limit : 1);
  c.braces = [];
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
  c.names = Scope.calloc(1, sizeof(struct GenNames));
  c.names.counters = {};
  c.names.adapters = {};
  c.names.file_scope_owners = {};
}

static Sym _new_sym(Compiler c) {
  Sym s = Scope.calloc(1, sizeof(struct Sym));
  s.compiler = c;
  s.binding_facts = {};
  s.scopes = Block.new(sizeof(SymScope));
  s.statics = {};
  return s;
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

/** Takes over `owner`'s macro, object-like `#define`, import, keyword, and
    Lisp state for one segment of a collected file. Segments are one
    translation unit, so a shadow uses the unit's Lisp environment rather
    than its own.
*/
void Compiler.take_unit_state(Compiler c, Compiler owner) {
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
  char resolved[PATH_MAX];
  return realpath(path, resolved) ? resolved : path;
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

// tokenizing

/** Scans source and positions the compiler at its first non-trivia token.

    The compiler borrows `text` for diagnostics and macro source capture until
    translation finishes.
*/
void Compiler.tokenize(Compiler c, char *text) {
  if (_is_script_file(c)) c.script = c.unit_script;
  c.input_boundary = NULL;
  c.text = text;
  c.tokenizer = Tokenizer.new(c.text, <x2c>);
  c.tokenizer.layout = c.layout || x2c_layout_file(c.filename);
  c.tokenizer.scan();
  c.layout = c.tokenizer.layout;
  _report_malformed_token(c);
  _scan_conditionals(c);
  _retag_keywords(c.tokenizer);
  c.token = _skip_forward(c.tokenizer.tokens);
  c.braces.clear();
}

/* The unit's script settings apply to the one file that carries the
   shebang, whichever compiler reads it. */
static int _is_script_file(Compiler c) =>
  c.unit_script && c.filename &&
  (c.filename == c.unit_script.path ||
   Path.absolute(c.filename) == c.unit_script.path);

/* A lexical failure truncates the token stream, so the parser reaches the
   appended `<eof>` and blames the end of the file. Report the refused byte
   instead. An `<incomplete>` token really did run out of source, so it keeps
   the end-of-file diagnostic that describes it. */
static void _report_malformed_token(Compiler c) {
  Symbol status = c.tokenizer.status();
  if (status != <malformed> && status != <indent>) return;
  String message =
    status == <indent> ? "inconsistent indentation" : "invalid token";
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <error>) c.report_error(<parse>, message, token, NULL);
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
       token = _skip_forward(token + 1)) {
    if (token.type == <in>) {
      Token next = _skip_forward(token + 1);
      if (!(prev && _ends_operand(prev.type) && _starts_operand(next.type)))
        token.type = <ident>;
    }
    else if (token.type == <match>) {
      Token next = _skip_forward(token + 1);
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
    token = _skip_forward(token + 1);
    steps--;
  }
  while (steps < 0) {
    token = _skip_backward(token - 1, c.tokenizer.tokens);
    steps++;
  }
  return token.type;
}

static Token _skip_forward(Token token) {
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

/** Returns the first non-trivia token at or after `token`. */
Token Compiler.skip_trivia_from(Compiler c, Token token) =>
  _skip_forward(token);

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
    c.report_error(<parse>, %"expected '$type'", c.token, NULL);
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
  c.token = _skip_forward(consumed + 1);
  _update_brace_stack(c, consumed);
}

static void _update_brace_stack(Compiler c, Token consumed) {
  if (!consumed) return;
  switch (consumed.type) {
    case <"{">: case <"%{">: case <"${">: case <"@{">:
      c.braces.push(consumed);
      break;
    case <"}">:
      if (c.braces.len()) c.braces.take_last();
      else {
        List notes = %( "encountered '}' without matching '{'" );
        c.report_error(<parse>, "unexpected '}'", consumed, notes);
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

static void _check_unmatched_braces(Compiler c) {
  if (!c.braces.len()) return;
  c.report_error(<parse>, "missing '}'", c.braces[-1], %( "'{' opened here" ));
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
  return t.type == <eof> ? t : _skip_forward(t + 1);
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

// source locations

/** Records a token's location and returns its one-based occurrence.

    A null token returns zero. Callers pass the token that opened a construct,
    so an `(at N node)` wrapper retains its start for transform diagnostics
    after `compiler.token` has reached end of file.
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
  List source_key = value, range = _source_range(c, first, after);
  if (!range) return;
  Map symbols = source_key.car();
  List key = source_key.cadr();
  Type type = symbols[key];
  List declaration = %(@range $type);
  c.source_declarations[source_key] = declaration;
  if (c.source_primary && !c.shallow) {
    c.source_definitions[binding] = declaration;
    c.source_occurrences.push(%(@range $binding $type));
  }
}

static List _source_range(Compiler c, Token first, Token after) {
  if (!first || !after || first >= after || c.macro_holes) return NULL;
  Token last = after - 1;
  while (last > first &&
         (last.type == <space> || last.type == <comment> ||
          last.type == <preproc>)) last--;
  String path = Path.absolute(c.filename);
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
  List range = _source_range(c, first, after);
  if (range) c.source_occurrences.push(%(@range $binding $type));
}

/** Carries declaration metadata with one actual symbol contribution. */
void Compiler.copy_source_declaration(
  Compiler c, Map target, Map source, List key) {
  if (!c.source_facts) return;
  Var declaration;
  List target_key = %($target $key);
  if (c.source_declarations.try_get(%($source $key), declaration))
    c.source_declarations[target_key] = declaration;
  else c.source_declarations.del(target_key);
}

/** Carries declaration metadata beside a completed symbol-map merge. */
void Compiler.merge_source_declarations(Compiler c, Map target, Map source) {
  if (!c.source_facts) return;
  foreach (Var key, source.keys())
    if (key is <list>) c.copy_source_declaration(target, source, key);
}

// preprocessor directives

/** Classifies an opening conditional directive by which of its arms C can
    never reach: `<first>` when the condition requires a never-defined name
    or is `0`, `<rest>` when it is exactly `!defined(NAME)`, else 0. Each
    never-defined name reads as `<never>`, which no C token spells. */
Symbol preproc_never_active_arm(String s) {
  Tokenizer scanned = Tokenizer.new(preproc_directive(s), <x2c>);
  scanned.scan();
  Array words = [];
  for (Token t = _skip_forward(scanned.tokens); t.type != <eof>;
       t = _skip_forward(t + 1))
    words.push(_never_defined(t.text) ? "<never>" : t.text);
  String line = " ".join(words.list_free()).replace(
    "defined ( <never> )", "defined <never>");
  // A `||` gives the condition another way to hold, so the arm can be taken.
  if (line == "ifdef <never>" || line == "if 0" || line == "if ( 0 )" ||
      line == "if defined <never>" ||
      (line.startswith("if defined <never> && ") && !line.contains(" || ")))
    return <first>;
  return line == "ifndef <never>" || line == "if ! defined <never>"
    ? <rest> : 0;
}

/* x2c output is compiled as C by a GNU-style compiler, so `__cplusplus` and
   `_MSC_VER` are never defined, and a compiler built for a host other than
   Windows never targets it. */
static int _never_defined(String name) {
  if (name == "__cplusplus" || name == "_MSC_VER") return 1;
#if defined(_WIN32) || defined(__CYGWIN__)
  return 0;
#else
  return name == "_WIN32" || name == "_WIN64" || name == "__CYGWIN__";
#endif
}

/** Returns the hidden-arm state of the conditional group that `text` opens:
    2 when C never takes its first arm, 1 when C never takes the arms after
    its first `#else`, and 0 otherwise. */
int preproc_open_state(String text) {
  Symbol never = preproc_never_active_arm(text);
  return never == <first> ? 2 : never == <rest>;
}

/** Returns a group's hidden-arm state after its `#elif` or `#else`: 2 when
    the group's state was 1, and 0 otherwise. */
int preproc_branch_state(int state) => state == 1 ? 2 : 0;

/** Returns 1 when the preprocessor line `text` is `#pragma private`, 0 when
    it is `#pragma public`, and -1 otherwise. A comment in the line reads as
    a blank, as it does in C. */
int preproc_visibility(String text) {
  String directive = preproc_directive(text);
  if (!directive.startswith("pragma")) return -1;
  Tokenizer scanned = Tokenizer.new(directive, <x2c>);
  scanned.scan();
  Array words = [];
  for (Token t = _skip_forward(scanned.tokens); t.type != <eof>;
       t = _skip_forward(t + 1))
    words.push(t.text);
  String line = " ".join(words.list_free());
  if (line == "pragma private") return 1;
  return line == "pragma public" ? 0 : -1;
}

/* Returns the name token of the `#define` or `#undef` directive `content`,
   or NULL for any other directive, and sets `*undefined` for `#undef`. The
   directive is scanned as x2c tokens. */
static Token _macro_directive(String content, int &undefined) {
  String directive = preproc_directive(content);
  undefined = directive.startswith("undef");
  if (!undefined && !directive.startswith("define")) return NULL;
  Tokenizer scanned = Tokenizer.new(
    directive.remove_prefix(undefined ? "undef" : "define"), <x2c>);
  scanned.scan();
  Token token = _skip_forward(scanned.tokens);
  return token.type == <ident> ? token : NULL;
}

/* conditional arms

   x2c output is always compiled as C by a GNU-style compiler, so an arm
   that only C++, MSVC, or `#if 0` reaches holds no syntax x2c needs to
   parse. Its tokens become comments; the directives around it stay in
   place, so emission is unchanged. */

/* One scan of a unit's tokens. `stack` holds the open conditional groups
   as `(id arm state)` entries; a group's state is 2 while its arm is
   hidden, 1 when the arms after its first `#else` will be, and 0
   otherwise. `layout` maps each macro whose body can change a struct's
   layout to 1, or to 2 when the body packs. */
typedef struct ArmScan {
  Compiler c, Array stack, Map layout;
  int hidden, serial;
} ArmScan;

/* Records the open groups after each conditional directive, and marks
   layout attributes where written or where a macro expands to one. */
static void _scan_conditionals(Compiler c) {
  Array stack = $auto([]);
  Map layout = $auto({});
  ArmScan scan = {.c = c, .stack = stack, .layout = layout};
  c.arm_stacks = {};
  c.layout_marks = [];
  c.packed_marks = [];
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <eof>) break;
    if (token.type == <preproc>) scan.directive(token, i);
    else i = scan.code(token, i);
  }
}

static void ArmScan.directive(ArmScan *s, Token token, size_t i) {
  Symbol kind = preproc_conditional_kind(token.text);
  int conditional = kind == <open> || (kind && s.stack.len());
  if (kind == <open>)
    s.stack.push(%(${++s.serial} 0 ${preproc_open_state(token.text)}));
  else if (kind == <branch> && s.stack.len()) {
    Var (id, arm, state) = s.stack[-1];
    s.stack[-1] = %($id ${arm.integer() + 1} ${preproc_branch_state(state)});
  }
  else if (kind == <close> && s.stack.len()) s.stack.take_last();
  else if (!s.hidden) _note_layout_macro(token.text, s.layout, s.stack.len());
  if (!conditional) return;
  s.c.arm_stacks[(long) i] = s.stack.list();
  s.hidden = _hidden_group(s.stack);
}

static int _hidden_group(Array stack) {
  foreach (List group, stack) if (group.caddr() == 2) return 1;
  return 0;
}

/* Hides a token of an arm C never takes and marks layout attributes, and
   returns the index of the token's last part. A lexical failure ends the
   token stream, so the rest of the unit is missing whichever arm holds it;
   the parser reports the `<error>` token rather than hiding it. */
static size_t ArmScan.code(ArmScan *s, Token token, size_t i) {
  if (s.hidden && token.type != <space> && token.type != <error>)
    token.type = <comment>;
  else if (token.type == <ident> && token.text == "__attribute__")
    return _note_attribute(s.c, i);
  else if (token.type == <ident> && token.text in s.layout)
    _mark_layout(s.c, i, s.layout[token.text] == 2);
  return i;
}

/* Records a pair of layout marks at the `__attribute__ ((...))` starting at
   token `index` when it can change a struct's layout. Returns the index of
   the attribute's last token. */
static size_t _note_attribute(Compiler c, size_t index) {
  Token base = c.tokenizer.tokens;
  Token open = _skip_forward(base + index + 1);
  if (open.type != <(>) return index;
  Token inner = _skip_forward(open + 1), last = open.group_close();
  if (last.type == <eof>) return index;
  int packed = 0;
  if (inner.type == <(> && _layout_attribute(inner, packed))
    _mark_layout(c, index, packed);
  return last - base;
}

/* A layout mark pair brackets the token at `index`, and a packing
   attribute adds a packed pair. */
static void _mark_layout(Compiler c, size_t index, int packed) {
  c.layout_marks.push((long) index);
  c.layout_marks.push((long) index + 1);
  if (!packed) return;
  c.packed_marks.push((long) index);
  c.packed_marks.push((long) index + 1);
}

/* Reports whether the attribute list the group `open` holds names an
   attribute that can change a struct's layout, spelled with or without its
   surrounding underscores. Identifiers inside an attribute's own arguments
   are not names. */
static int _layout_attribute(Token open, int &packed) {
  Token close = open.group_close();
  int depth = 0, layout = 0;
  for (Token t = open; t < close; t++) {
    depth += t.type.group_step();
    if (depth != 1 || t.type != <ident>) continue;
    String word = t.text.strip("_");
    if (word == "packed") {
      layout = 1;
      packed = 1;
    }
    else if (word == "aligned" || word == "mode" ||
             word == "vector_size") layout = 1;
  }
  return layout;
}

/* Tracks in `layout` the macros whose body holds an attribute that can
   change a struct's layout, written out or through another such macro. A
   use of one is marked as the attribute it expands to would be. As with
   layout, a macro that any arm defines with such an attribute stays in
   `layout`; only an `#undef` or definition outside every conditional group,
   `conditional` false, removes it. */
static void _note_layout_macro(String content, Map layout, int conditional) {
  int undefined;
  Token name = _macro_directive(content, undefined);
  if (!name) return;
  if (!conditional) layout.del(name.text);
  if (undefined) return;
  Token token = name + 1;
  if (token.type == <(>) token = token.after_group();
  int value = 0;
  for (; token.type != <eof>; token = _skip_forward(token + 1)) {
    if (token.type != <ident>) continue;
    int level = _word_layout(token, layout);
    if (level > value) value = level;
  }
  if (value && (!layout.contains(name.text) || layout[name.text] < value))
    layout[name.text] = value;
}

/* The layout level one word of a macro body contributes: an attribute's
   own level, or the level of the layout macro it names. */
static int _word_layout(Token token, Map layout) {
  if (token.text == "__attribute__") return _attribute_layout(token);
  if (token.text in layout) return layout[token.text];
  return 0;
}

/* 2 for a packing `__attribute__` at `token`, 1 for another attribute that
   can change a struct's layout, and 0 otherwise. */
static int _attribute_layout(Token token) {
  Token open = _skip_forward(token + 1);
  Token inner = open.type == <(> ? _skip_forward(open + 1) : open;
  int packed = 0;
  if (inner.type != <(> || !_layout_attribute(inner, packed)) return 0;
  return packed ? 2 : 1;
}

// leading directives

/** Returns source-ordered preprocessor nodes in the preceding trivia.

    Spaces and comments remain trivia rather than becoming AST nodes.
*/
List Compiler.leading_preproc(Compiler c) {
  List noncode = %();
  Token base = c.tokenizer.tokens, token = c.token;
  if (token == base) return NULL;
  while (--token >= base) {
    if (token.type == <preproc>)
      noncode = cons(%( preproc ${token.text} ), noncode);
    else if (token.type != <space> && token.type != <comment>) break;
  }
  return noncode;
}

/** Applies public and private pragma directives to source visibility state
    and records each object-like `#define` name, less those `#undef` drops,
    for the literal warning.

    A negative visibility state disables pragma tracking for this token
    stream; macro names are recorded regardless.
*/
void Compiler.update_source_visibility(Compiler c, List directives) {
  foreach (List directive, directives) _note_object_macro(c, directive.cadr());
  if (c.source_private < 0) return;
  foreach (List directive, directives) {
    int visibility = preproc_visibility(directive.cadr());
    if (visibility >= 0) c.source_private = visibility;
  }
}

/* Records the name of each `#define` so a bare atom spelled the same way
   inside a literal can be flagged and a declaration prefix can be read.
   The directive after `#define` is scanned as x2c tokens. An `#undef`
   drops the name, so later source reads it as an ordinary identifier. */
static void _note_object_macro(Compiler c, String content) {
  int undefined;
  Token token = _macro_directive(content, undefined);
  if (!token) return;
  String name = token.text;
  Token body = token + 1;
  if (undefined) c.object_macros.del(name);
  // A parameter list touching the name makes the macro function-like.
  else if (body.type == <(>) _note_function_macro(c, name, body);
  else _note_prefix_macro(c, name, _skip_forward(body));
}

/* A function-like macro whose body is empty or an attribute is an
   `<annotation>`, and one that wraps its parameter is a `<wrapper>`; any
   other function-like macro is skipped. */
static void _note_function_macro(Compiler c, String name, Token params) {
  Token after = params.after_group(), String param = NULL;
  Token first = _skip_forward(params + 1);
  if (first.type == <ident> && _skip_forward(first + 1).type == <)>)
    param = first.text;
  Var kind = _macro_prefix(c, after, param);
  if (kind.equal(%())) c.object_macros[name] = <annotation>;
  else if (kind.equal(<wrapper>)) c.object_macros[name] = <wrapper>;
}

/* An object-like body is classified by `_macro_prefix`. A name another arm
   defines to anything but a string literal is no string literal:
   `Var v = SEP;` must not make a String of the other arm's number. */
static void _note_prefix_macro(Compiler c, String name, Token body) {
  Var definition = _macro_prefix(c, body, NULL), existing;
  if (!c.object_macros.try_get(name, existing) ||
      _prefix_rank(definition) > _prefix_rank(existing) ||
      (existing.equal(<string>) && !definition.equal(<string>)))
    c.object_macros[name] = definition;
}

/* Classifies a macro body, scanned as x2c tokens, by the declaration prefix
   it contributes: the `List` of its specifier words, which are storage
   classes, `inline`, qualifiers, builtin types, and the words of other
   prefix macros, amid attributes that contribute nothing; `<wrapper>` when
   a function-like body is its parameter `param` amid prefixes; `<string>`
   for a string literal; and 1 for any other text. */
static Var _macro_prefix(Compiler c, Token token, String param) {
  if (token.type == <lit-char*>) return <string>;
  Array words = [], int wrapped = 0;
  while (token.type != <eof>) {
    Symbol type = token.type, String word = token.text;
    Var definition;
    Token next = _skip_forward(token + 1);
    if (_is_specifier(type)) words.push(type);
    else if (type == <lit-char*>);   // the linkage name in `extern "C"`
    else if (type != <ident>) return 1;
    else if (_is_annotation(c, word)) {
      if (next.type != <(>) return 1;
      next = next.after_group();
    }
    else if (param && word == param && !wrapped) wrapped = 1;
    else if (!c.object_macros.try_get(word, definition) ||
             definition is not <list>)
      return 1;
    else foreach (Var item, definition) words.push(item);
    token = next;
  }
  return wrapped ? <wrapper> : words.list_free();
}

static int _is_specifier(Symbol type) =>
  type.is_storage_class() || type.is_inline() || type.is_type_qualifier() ||
  type.is_builtin_type();

static int _is_annotation(Compiler c, String word) {
  Var definition;
  return word == "__attribute__" || word == "__declspec" ||
         (c.object_macros.try_get(word, definition) &&
          definition.equal(<annotation>));
}

/* Ranks prefix classifications so a name defined differently in two
   conditional arms keeps the reading that emits correct C: `static` hides
   a definition from the header, so it wins; a qualifier that another arm
   omits, as zlib's `z_const` is `const` or nothing, rejects writes that C
   accepts in that arm, so it loses to any other prefix; other text loses to
   any prefix. */
static int _prefix_rank(Var v) {
  if (v is not <list>) return 0;
  if (List.match(v, %(* static *))) return 4;
  foreach (Symbol word, v) if (word.is_type_qualifier()) return 1;
  return v.list() ? 3 : 2;
}

// symbol scopes

/*  Symbol table implemented as stack of maps (scopes). Each map represents
    a scope level. Symbol lookup searches from top to bottom of stack.

    Type grammar:
      TYPE-LIST : ( TYPE+ )
      TYPE      : ( MOD* SPEC )
      MOD       : (array SIZE?) | * | & | FUNCTION
      FUNCTION  : ( (func TYPE-LIST) MOD* SPEC)
      SPEC      : SCALAR | (union U) | (struct S) | (enum E) | TYPEDEF
      SCALAR    : "any C basic type"
      TYPEDEF   : "any user defined type"

    Symbol table entries:

    Identifier categories:
      V: variable name
      E: enum tag name
      F: function name
      K: field name (key)
      M: method name
      S: struct tag name
      U: union tag name
      T: typedef name

    Entry formats:
      ____________            ____________________________
      Lookup Key              Type Result (value in table)
      ------------            ----------------------------
      (V)                     TYPE
      (union U K)             TYPE
      (union U)               (union TYPE-LIST)
      (struct S K)            (TYPE)
      (struct S)              (struct TYPE-LIST)
      (enum E)                (enum)
      (class C M)             (func ...)
      (T)                     (typedef TYPE)
      (F)                     (func (TYPE-LIST) TYPE)

    Notes:
    - Struct fields can have (BIT N) mods as well.
    - "long", "long long", and "double double" are all omitted to keep
      sizeof(Var) to 8 bytes.
    - A declaration like "struct { int a, b; } x;" will generate two
      symbol table entries: one for an anonymous struct definition, and the
      other for x, which references the named anonymous struct definition.
*/
static SymScope *_semantic_scope(Sym s, int index) {
  int count = s.scopes.len();
  if (index < 0) index += count;
  if (index < 0 || index >= count) return NULL;
  SymScope *scopes = s.scopes.bytes;
  return scopes + index;
}

/** Resets symbol state to one base scope backed by `globals`.

    Later definitions mutate that caller-supplied map.
*/
void Sym.reset(Sym s, Map globals) {
  _clear_symbols(s, globals, 1);
  _push_symbols(s, s.globals);
}

/* An overlay reads `base` below the writable scope `overlay`. */
static void Sym._reset_overlay(Sym s, Map base, Map overlay) {
  _clear_symbols(s, overlay, 2);
  _push_symbols(s, base != NULL ? base : {});
  _push_symbols(s, s.globals);
}

static void _clear_symbols(Sym s, Map globals, int base_scopes) {
  s.scopes.clear();
  s.globals = globals != NULL ? globals : {};
  s.statics = {};
  s.base_scopes = base_scopes;
  s.local_macro_names = 0;
  s.binding_facts = {};
}

static void _push_symbols(Sym s, Map symbols) {
  struct SymScope scope = {
    .symbols = symbols, .bindings = {}, .enumerators = {}};
  s.scopes.push(&scope);
}

/** Pushes a new empty lexical scope. */
void Sym.push_new_scope(Sym s) => _push_symbols(s, {});

/** Pushes a caller-supplied lexical scope while retaining its map objects. */
void Sym.push_scope(Sym s, SymScope scope) {
  s.scopes.push(&scope);
}

/** Pops the innermost scope, or returns an empty scope when none exists. */
SymScope Sym.pop_scope(Sym s) {
  struct SymScope scope = { 0 };
  s.scopes.try_pop(&scope);
  if (scope.macros != NULL) s.local_macro_names -= scope.macros.len();
  return scope;
}

/** Returns the number of semantic scopes, including base scopes. */
int Sym.scope_count(Sym s) => s.scopes.len();

/** Returns whether declarations currently bind at file scope. */
int Sym.at_file_scope(Sym s) => (int) s.scopes.len() <= s.base_scopes;

// symbol maps

/** Returns the mutable global symbol map supplied to the latest reset. */
Map Sym.global_symbols(Sym s) => s.globals;

/** Copies all base-scope symbols into a fresh map in source order.

    Package collection uses this so it resolves against the prelude and the
    importing unit's already-visible includes without mutating either.
*/
Map Sym.base_symbols(Sym s) {
  Map seed = {};
  for (int i = 0; i < s.base_scopes; i++)
    seed.merge(_semantic_scope(s, i).symbols);
  return seed;
}

/** Returns the current scope's mutable symbol map, or `NULL`. */
Map Sym.current_symbols(Sym s) {
  SymScope *scope = _semantic_scope(s, -1);
  return scope ? scope.symbols : NULL;
}

/** Returns the current borrowed set of file-static declaration keys.

    A semantic transaction may replace this map, so reacquire it afterwards.
*/
Map Sym.file_statics(Sym s) => s.statics;

/** Marks a declaration key as file-static. */
void Sym.mark_static(Sym s, List key) {
  s.statics[key] = 1;
}

/** Returns the visible one-part source names and their semantic types.
    Inner scopes win. The result is a fresh List; types remain borrowed. */
List Sym.visible_symbols(Sym s) {
  Map seen = {};
  Array rows = [];
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--) {
    SymScope *scope = _semantic_scope(s, i);
    foreach (Var (key, value), scope.symbols)
      match (key)
        case %(?(String name)):
          if (_unseen(seen, name)) rows.push(%($name $value));
    if (scope.macros != NULL)
      foreach (Var (name, definition), scope.macros)
        if (name is <string> && _unseen(seen, name))
          rows.push(%($name ${_macro_kind(definition)}));
  }
  return rows.list_free();
}

static int _unseen(Map seen, Var name) {
  if (seen.contains(name)) return 0;
  seen[name] = 1;
  return 1;
}

static Symbol _macro_kind(Var definition) {
  Symbol kind = definition is <list> ? definition.list().assoc(<kind>) : 0;
  return kind == <type> ? <typemacro> : <macro>;
}

// definitions

/** Sets a semantic type for `key` in the required active scope. */
void Sym.set(Sym s, List key, List type) {
  SymScope *current = _semantic_scope(s, -1);
  Map scope = current.symbols;
  if (log_should_log(<debug>, <symtab>))
    log_debug(<symtab>, %( (func "Sym.set") (key $key) (val $type) ));
  scope[key] = type;
  if (_retained_member(key)) s.binding_facts[%(aggfact $key)] = type;
}

static int _retained_member(List key) =>
  !!key.match(%((!or struct union) (!or (binding ? ?) (gensym ? ?)) ? *));

/** Defines `key` and returns its stable binding in the active scope. */
List Sym.define(Sym s, List key, List type) {
  SymScope *scope = _semantic_scope(s, -1);
  s.set(key, type);
  _seed_var_tag(key, type);
  return _semantic_scope_binding(s, scope, key);
}

static void _seed_var_tag(List key, List type) {
  String owner = _var_converter_owner(key, type);
  if (!owner) return;
  String converter = %"${owner}_var", Type declared = %($owner);
  declared.register_var_tag(owner, converter);
}

/* A declared `Var T.var(T)` is the conformance marker that lets a named
   type box like a builtin. Keep its tag and exact converter in the active
   translation unit rather than the process-lifetime builtin table. */
static String _var_converter_owner(List key, List type) {
  match (type)
    case %((func ((?(String named)))) "Var"): {
      String owner = named, converter = %"${owner}_var";
      match (key)
        case %(?(String spelling)):
          return spelling == converter ? owner : NULL;
    }
  return NULL;
}

/** Registers declared `T_var` converters in the active `Type` unit. */
void Sym.seed_var_tags(Sym s, Map symbols) {
  if (!symbols) return;
  foreach (Var (key, type), symbols)
    if (key is <list> && type is <list>) _seed_var_tag(key, type);
}

/** Defines `key` in the unit's writable base scope.

    The definition survives the expression scope that first resolved it. Its
    binding is issued at the first reference, as for a row an included file
    contributes, so the unit numbers its bindings the same whether it defined
    the row here or replayed it from an interface.
*/
void Sym.define_global(Sym s, List key, List type) {
  SymScope *scope = _semantic_scope(s, s.base_scopes - 1);
  scope.symbols[key] = type;
  _seed_var_tag(key, type);
}

/** Associates an enumerator key with its owner in the active scope. */
void Sym.declare_enumerator(Sym s, List key, Symbol owner) {
  SymScope *scope = _semantic_scope(s, -1);
  if (scope) scope.enumerators[key] = owner;
}

// bindings

static List _semantic_scope_binding(Sym s, SymScope *scope, List key) {
  Var found;
  List binding;
  if (scope.bindings.try_get(key, found)) binding = found;
  else {
    binding = _semantic_new_binding(s, key);
    scope.bindings[key] = binding;
  }
  (Var binding_tag, int identity, String spelling) = binding;
  (void) binding_tag;
  if (!s.binding_facts.contains(%(known $identity)))
    s.binding_facts[%(known $identity)] = spelling;
  List self_key = %(self $binding);
  if (!s.binding_facts.contains(self_key)) {
    Var relative;
    if (scope.symbols.try_get(%(self $spelling), relative))
      s.binding_facts[self_key] = relative;
  }
  if (s.compiler.source_facts) _note_source_key(s, scope, key, binding);
  return binding;
}

/* Source facts find a binding's declaration through the map and key that
   hold its symbol row. */
static void _note_source_key(Sym s, SymScope *scope, List key, List binding) {
  Compiler c = s.compiler;
  List source_key = %(${scope.symbols} $key);
  s.binding_facts[%(src-key $binding)] = source_key;
  Var declaration;
  if (c.source_primary && !c.shallow &&
      c.source_declarations.try_get(source_key, declaration))
    c.source_definitions[binding] = declaration;
}

static List _semantic_new_binding(Sym s, List key) {
  int identity = ++s.compiler.names.next_binding;
  Var name = key.last();
  List binding = binding_identity_new(identity, name);
  s.binding_facts[%(known $identity)] = name;
  return binding;
}

/** Allocates a fresh binding identity for a compiler-introduced spelling. */
List Sym.introduce(Sym s, String spelling) =>
  _semantic_new_binding(s, %($spelling));

/** Returns `key`'s binding in the current scope, or `NULL`. */
List Sym.current_binding(Sym s, List key) {
  SymScope *scope = _semantic_scope(s, -1);
  Var binding;
  return scope && scope.bindings.try_get(key, binding) ? binding : NULL;
}

/** Returns the current scope's enum owner for `key`, or zero. */
Symbol Sym.enumerator_owner(Sym s, List key) {
  SymScope *scope = _semantic_scope(s, -1);
  Var owner;
  return scope && scope.enumerators.try_get(key, owner) ? owner : 0;
}

/** Reports whether `binding` belongs to a scope inside the base scopes. */
int Sym.binding_is_local(Sym s, List binding) =>
  s.binding_is_local_before(binding, s.scopes.len());

/** Reports whether `binding` belongs to a local scope below `scope_count`.

    Counts beyond the current scope depth are clamped to that depth.
*/
int Sym.binding_is_local_before(Sym s, List binding, int scope_count) {
  if (scope_count > (int) s.scopes.len()) scope_count = s.scopes.len();
  for (int i = scope_count - 1; i >= s.base_scopes; i--)
    foreach (Var (_, candidate), _semantic_scope(s, i).bindings)
      if (List.equal(candidate, binding)) return 1;
  return 0;
}

// lookup

/** Returns `key`'s type, retrying a bare key in package space, or `NULL`. */
List Sym.get(Sym s, List key) {
  List found = s.get_exact(key);
  if (found) return found;
  List retry = _package_retry_key(s, key);
  return retry ? s.get_exact(retry) : NULL;
}

/** Returns `key`'s type without package fallback, or `NULL`. */
List Sym.get_exact(Sym s, List key) {
  Var val;
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--) {
    Map scope = _semantic_scope(s, i).symbols;
    if (scope.try_get(key, val)) return val;
  }
  if (_retained_member(key) &&
      s.binding_facts.try_get(%(aggfact $key), val)) return val;
  return NULL;
}

/* Package files may reference their own file-scope names bare. A plain-key
   total miss retries the package-prefixed key; exact entries win, and
   units outside package mode never retry. */
static List _package_retry_key(Sym s, List key) {
  String package = s.compiler.package;
  if (!package || !key || key.cdr() || key.car() is not <string>) return NULL;
  String spelling = key.car();
  String prefixed = s.compiler.package_spelling(spelling);
  return prefixed == spelling ? NULL : %($prefixed);
}

/** Resolves an existing key and optionally stores its semantic type.

    A symbol row without a binding receives a stable binding identity. A total
    miss returns `NULL` and stores `NULL` through `type` when provided.
*/
List Sym.lookup(Sym s, List key, Type &?type) =>
  _semantic_lookup(s, key, type, (int) s.scopes.len() - 1, 0);

/** Resolves `key` or creates a forward binding in the current scope.

    Stores `NULL` through `type` when no declaration supplies a type.
*/
List Sym.reference(Sym s, List key, Type &?type) =>
  _semantic_lookup(s, key, type, (int) s.scopes.len() - 1, 1);

/** Resolves a binding through base scopes and optionally stores its type.

    Returns `NULL` when no base scope contains the key.
*/
List Sym.resolve_global(Sym s, List key, Type &?type) =>
  _semantic_lookup(s, key, type, s.base_scopes - 1, 0);

/** Resolves a global name or creates its forward binding in the base scope.
    Local declarations cannot capture a retained macro's global reference.
*/
List Sym.reference_global(Sym s, List key) {
  List binding = s.resolve_global(key, NULL);
  return binding ? binding : _semantic_scope_binding(
    s, _semantic_scope(s, s.base_scopes - 1), key);
}

static List _semantic_lookup(
  Sym s, List key, Type &?type, int first, int forward) {
  Var found;
  for (int i = first; i >= 0; i--) {
    SymScope *scope = _semantic_scope(s, i);
    if (scope.symbols.try_get(key, found)) {
      if (type) type = found;
      return _semantic_scope_binding(s, scope, key);
    }
    if (scope.bindings.try_get(key, found)) {
      if (type) type = NULL;
      return found;
    }
  }
  List retry = _package_retry_key(s, key);
  if (retry && (!forward || s.get_exact(retry)))
    return _semantic_lookup(s, retry, type, first, forward);
  if (type) type = NULL;
  return forward
       ? _semantic_scope_binding(s, _semantic_scope(s, -1), key)
       : NULL;
}

// declarations

/** Analyzes a complete declaration type and installs its stored declared type.

    Returns the declared binding. At file scope this also records static
    visibility; local declarations record automatic-storage and declared-type
    facts. Stored types discard storage and `inline` while retaining `const`,
    `restrict`, and `volatile`.
*/
List Sym.declare(Sym s, List context, List key, List ast) {
  if (s.compiler.package) key = _package_declared_key(s, context, key, ast);
  _check_spelling(s.compiler, _declared_spelling(key));
  Type ctxkey = %( @context @key ), type = ast.type_from_ast();
  Type declared_type = type;
  if ((int) s.scopes.len() == s.base_scopes && !context)
    _track_static(s, (List) ctxkey, ast);
  List binding = NULL;
  if (context === %(typedef)) binding = s.define(key, (List) ctxkey);
  type = _stored_type(type, ctxkey, ast);
  if (!binding) binding = s.define(ctxkey, (List) type);
  else {
    s.set(ctxkey, (List) type);
    _local_typedef(s, type, binding);
  }
  if (!context && !s.at_file_scope())
    _local_object(s, key, binding, declared_type);
  return binding;
}

/* Package mode rewrites file-scope non-static declaration keys into the
   package's `name__` space, so binding spellings, aggregate tags, and
   derived Var converters carry the prefix everywhere they are read.
   Statics keep their spellings (C internal linkage); anonymous aggregate
   gensyms are not source spellings and stay in the compiler's space. */
static List _package_declared_key(Sym s, List context, List key, List ast) {
  Compiler c = s.compiler;
  if ((int) s.scopes.len() != s.base_scopes) return key;
  if (context && !(context === %(typedef))) return key;
  if (ast.type().is_static()) return key;
  Var (head, tag) = key;
  if (head is <string> && !key.cdr()) return %(${c.package_spelling(head)});
  if ((head == <struct> || head == <union> || head == <enum>) &&
      key.cdr() && !key.cddr() && tag is <string>)
    return %($head ${c.package_spelling(tag)});
  return key;
}

// The declared spelling, when the key names one.  Aggregate keys carry the
// tag in their second slot; anonymous aggregates carry a gensym list there
// and are not source spellings.
static String _declared_spelling(List key) {
  Var (head, tag) = key;
  if (head is <string>) return head;
  if (head == <struct> || head == <union> || head == <enum>)
    if (tag is <string>) return tag;
  return NULL;
}

/* A source declaration may not take a compiler-generated spelling or one
   in an imported package's space. A shallow parse reads emitted C, where
   generated spellings are the compiler's own output rather than a source
   declaration. */
static void _check_spelling(Compiler c, String spelling) {
  if (!c.shallow && _is_reserved_spelling(spelling)) {
    String message = %"'$spelling' is reserved for compiler-generated names";
    c.report_error(<parse>, message, c.token, NULL);
  }
  String owner = _package_reserved_owner(c, spelling);
  if (owner)
    c.report_error(
      <parse>, %"'$spelling' is reserved for imported package '$owner'",
      c.token, NULL);
}

// A source declaration may not enter the compiler's generated-name space.
// Checked once per declaration; no prepass over the token stream.
static int _is_reserved_spelling(String s) {
  if (!s) return 0;
  if (s.startswith("_x2c_")) return 1;
  if (s == "_init_guard_") return 1;
  if (s == "_file_init_") return 1;
  if (s.len() < 2 || s[0] != '_') return 0;
  for (int i = 1; i < s.len(); i++) if (s[i] < '0' || s[i] > '9') return 0;
  return 1;
}

/* Only packages imported by this unit reserve their `name__` space; foreign
   headers may contain `__`, and a package unit keeps its own prefix. */
static String _package_reserved_owner(Compiler c, String spelling) {
  if (!spelling || !c.package_aliases.len()) return NULL;
  foreach (Var (alias, value), c.package_aliases) {
    String name = value;
    if (name == c.package) continue;
    if (spelling.startswith(%"${name}__")) return name;
  }
  return NULL;
}

/* File-local globals are tracked for protocol and static initializer
   checks. The storage class is only visible here, before canonicalization
   strips it. */
static void _track_static(Sym s, List key, List ast) {
  if (ast.type().is_static()) s.statics[key] = 1;
  else s.statics.del(key);
}

// A tagged definition also publishes its tag unless the key is that tag.
static Type _stored_type(Type type, Type key, List ast) {
  if (type.is_aggregate_tag_body() && !key.is_aggregate_tag()) {
    Var (aggregate, tag) = ast;
    type = %( $aggregate $tag );
  }
  return type.declared();
}

/* A block-local typedef emits under a fresh spelling, and a local tag
   records its named type. */
static void _local_typedef(Sym s, Type type, List binding) {
  if (s.at_file_scope()) return;
  if (type.is_aggregate_tag()) s.binding_facts[%(ntype $binding)] = type;
  s.binding_facts[%(emitted $binding)] =
    s.compiler.fresh_name("local_typedef");
}

/* A local object records its automatic storage and declared type. One that
   shadows a declared `T_var` converter emits under a fresh spelling, so
   generated boxing still reaches the converter. */
static void _local_object(Sym s, List key, List binding, Type type) {
  _mark_automatic(s, binding, type);
  Type global_type = NULL;
  s.resolve_global(key, global_type);
  if (_var_converter_owner(key, global_type) &&
      !s.binding_facts.contains(%(emitted $binding)))
    s.binding_facts[%(emitted $binding)] =
      s.compiler.fresh_name("var_converter_shadow");
}

static void _mark_automatic(Sym s, List binding, Type type) {
  s.binding_facts[%(automatic $binding)] = 1;
  s.binding_facts[%(type $binding)] = type;
}

/** Installs an existing binding with `ast`'s qualifier-preserving type. */
List Sym.bind_identity(Sym s, List context, List binding, List ast) {
  String spelling = binding_identity_spelling(binding);
  List key = context ? %(@context $spelling) : %($spelling);
  SymScope *scope = _semantic_scope(s, -1);
  Type annotation = ast.type_from_ast();
  scope.symbols[key] = annotation.declared();
  if (context === %(typedef)) {
    key = %($spelling);
    scope.symbols[key] = %(typedef $spelling);
    _local_typedef(s, annotation, binding);
  }
  scope.bindings[key] = binding;
  if (!context && !s.at_file_scope()) _mark_automatic(s, binding, annotation);
  return binding;
}

/** Binds a local aggregate tag before its fields, preserving native spelling.
    A reference reuses the nearest visible tag; a definition or standalone
    forward declaration introduces the tag in the current lexical scope. A
    macro template names its tags as template locals.
*/
Var Compiler.aggregate_name(
  Compiler c, Symbol kind, Var name, int definition) {
  Sym s = c.sym;
  if (name is not <string>) return name;
  if (c.macro_holes) {
    List local = c.macro_tag_name(kind, name, definition);
    return local ? local : name;
  }
  Type type = %($kind $name);
  if (s.at_file_scope()) {
    /* Only a definition or standalone forward owns this package tag.
       A field or prototype may merely refer to a tag from a C header. */
    if (definition && !s.get_exact(type)) s.declare(NULL, type, type);
    return name;
  }
  if (!definition && s.get_exact(type)) return s.local_type(type).cadr();
  if (!definition && c.shallow) return name;
  List binding = s.current_binding(type);
  if (!binding) binding = s.declare(NULL, type, type);
  return binding;
}

// package names

/** Returns a name in the current package namespace, preserving prefixes.

    Idempotence lets parsing and declaration rewrites share this operation.
*/
String Compiler.package_spelling(Compiler c, String name) {
  if (!c.package || !name) return name;
  String prefix = %"${c.package}__";
  return name.startswith(prefix) ? name : %"$prefix$name";
}

/** Registers one local package alias.

    Shallow collection and full parsing both see an import, so repeating the
    same package and alias is a no-op. Another binding of the local spelling
    is a parse error.
*/
void Compiler.register_package_alias(
  Compiler c, String name, String alias, Token token) {
  Var bound = c.package_aliases[alias];
  if (bound is not void && bound == name) return;
  _check_package_binding(c, "alias", alias, token);
  c.package_aliases[alias] = name;
}

/** Registers one package member under a bare local spelling.

    The package member must already exist in the symbol table. Repeating the
    same binding is a no-op; any conflicting local binding is an error.
*/
void Compiler.register_package_member(
  Compiler c, String name, String member, String local,
  Token member_token, Token local_token) {
  /* Keep the source spellings so a later conflict says `geo.Vec` rather
     than naming the package-prefixed C symbol. */
  List binding = %($name $member);
  Var bound = c.package_members[local];
  if (bound is not void && bound.list() === binding) return;
  String spelling = %"${name}__$member";
  if (!c.sym.get_exact(%($spelling)))
    c.report_error(
      <parse>, %"package '$name' has no public name '$member'",
      member_token, NULL);
  _check_package_binding(c, "name", local, local_token);
  c.package_members[local] = binding;
}

/* An alias and a `with` name each claim one local spelling. Rebinding that
   spelling, or taking one a declaration already uses, is the same conflict.
   Both messages name what the developer wrote. */
static void _check_package_binding(
  Compiler c, String kind, String local, Token token) {
  Var alias = c.package_aliases[local];
  Var member = c.package_members[local];
  String bound = alias is void ? NULL : alias;
  if (!bound && member is not void) {
    List pair = member;
    (String package, String member_name) = pair;
    bound = %"$package.$member_name";
  }
  if (bound)
    c.report_error(
      <parse>, %"package $kind '$local' is already bound",
      token, %( "bound to: $bound" ));
  if (c.sym.get_exact(%($local)))
    c.report_error(
      <parse>, %"package $kind '$local' collides with a declared name",
      token, NULL);
}

/** Returns a visible `with` name's package-prefixed spelling, or `NULL`.

    An ordinary declaration of the local spelling shadows the `with` name.
*/
String Compiler.package_member_spelling(Compiler c, String name) {
  if (!c.package_members.len()) return NULL;
  Var bound = c.package_members[name];
  if (bound is void || c.sym.get_exact(%($name))) return NULL;
  List pair = bound;
  (String package, String member_name) = pair;
  return %"${package}__$member_name";
}

/** Returns sorted imported packages that publish `name`.

    Package-owned methods use `<package>__<Type>_<member>` internally while
    consumers retain the spelling from the package header. Sorting keeps
    ambiguity diagnostics deterministic.
*/
List Compiler.imported_providers(Compiler c, String name) {
  if (!name || !c.package_roots.len()) return NULL;
  List packages = %();
  foreach (Var (key, root), c.package_roots) {
    String package = key;
    if (c.sym.get_exact(%("${package}__$name")))
      packages = cons(package, packages);
  }
  return packages.sort();
}

/** Returns an unambiguous imported spelling for `name`, or `NULL`. */
String Compiler.imported_spelling(Compiler c, String name) {
  List packages = c.imported_providers(name);
  if (!packages || packages.cdr()) return NULL;
  return %"${packages.car()}__$name";
}

// local macros

/** Defines or replaces a macro in the active lexical scope.

    Captured bindings are recorded for later shadow handling. Replacing a
    name already defined in this scope does not increase the local macro
    count.
*/
void Sym.define_macro(Sym s, Atom name, List definition) {
  SymScope *scope = _semantic_scope(s, -1);
  if (scope.macros == NULL) scope.macros = {};
  if (!scope.macros.contains(name)) s.local_macro_names++;
  scope.macros[name] = definition;
  Var captures = definition.assoc(<captures>);
  if (captures is <list>) foreach (Var capture, captures.list())
    if (capture is <list>)
      s.binding_facts[%(local-macro-capture ${capture.list()})] = 1;
}

/** Returns whether any lexical scope contains a local macro definition. */
int Sym.has_local_macros(Sym s) => s.local_macro_names != 0;

/** Returns the innermost visible local macro named `name`, or `NULL`. */
List Sym.lookup_macro(Sym s, Atom name) {
  Var definition;
  for (int i = (int) s.scopes.len() - 1; i >= s.base_scopes; i--) {
    SymScope *scope = _semantic_scope(s, i);
    if (scope.macros != NULL && scope.macros.try_get(name, definition))
      return definition;
  }
  return NULL;
}

/** Returns the active macro definition's borrowed local map, or `NULL`. */
Map Compiler.macro_definition_locals(Compiler c) {
  Var stored = c.macro_holes[%(locals)];
  return stored is <map> ? stored : NULL;
}

// semantic transactions

typedef struct SymTxn {
  Compiler compiler;
  int scope_index, next_binding, active, String initializer_name;
  String shutdown_name, Map counters;
  int local_macro_names;
  SymScope scope;
  Map statics, binding_facts;
  Map source_definitions;
  int source_occurrences;
  /* A macro value application extends coverage to the effects its
     producers request: adapters, base-scope bindings, early declarations,
     initializers, origins, and exception support. */
  int extended, Map adapters, Array base_bindings;
  int early_count, init_count, origin_count, origin, needs_exception;
} *SymTxn;

/** Begins a reversible transaction over the current semantic scope.

    The transaction stages the current scope maps, file-static and binding
    facts, compile-time struct layouts, binding and generated-name
    counters, and initializer names. It does not snapshot parser position or
    other compiler state.
*/
SymTxn Compiler.begin_semantic_transaction(Compiler c) {
  SymTxn transaction = Scope.calloc(1, sizeof(struct SymTxn));
  transaction.compiler = c;
  transaction.scope_index = c.sym.scopes.len() - 1;
  SymScope *scope = _semantic_scope(c.sym, transaction.scope_index);
  transaction._save(*scope);
  if (transaction.extended) transaction._save_effects();
  if (c.source_facts && c.source_primary) transaction._save_sources();
  transaction._stage(scope);
  transaction.active = 1;
  return transaction;
}

static void SymTxn._save(SymTxn s, SymScope scope) {
  Compiler c = s.compiler;
  s.scope = scope;
  s.counters = c.names.counters;
  s.statics = c.sym.statics;
  s.binding_facts = c.semantic_binding_facts();
  s.next_binding = c.names.next_binding;
  s.local_macro_names = c.sym.local_macro_names;
  s.initializer_name = c.init_fn;
  s.shutdown_name = c.fini_fn;
  s.extended = c.macro_application > 0;
}

/* The base scopes other than the active one get fresh binding maps; the
   transaction keeps the originals. */
static void SymTxn._save_effects(SymTxn s) {
  Compiler c = s.compiler;
  s.adapters = c.names.adapters;
  s.base_bindings = [];
  s.early_count = c.early_decls.len();
  s.init_count = c.inits.len();
  s.origin_count = c.origins.len();
  s.origin = c.origin;
  s.needs_exception = c.needs_exception;
  c.names.adapters = c.names.adapters.copy();
  for (int i = 0; i < c.sym.base_scopes; i++) {
    if (i == s.scope_index) continue;
    SymScope *base = _semantic_scope(c.sym, i);
    s.base_bindings.push(%($i ${base.bindings}));
    base.bindings = base.bindings.copy();
  }
}

static void SymTxn._save_sources(SymTxn s) {
  s.source_definitions = s.compiler.source_definitions.copy();
  s.source_occurrences = s.compiler.source_occurrences.len();
}

/* Macro binding is incremental. Copy only the maps that construction
   mutates so failure can discard its rows while reads still reach the
   unchanged outer scopes. */
static void SymTxn._stage(SymTxn s, SymScope *scope) {
  Compiler c = s.compiler;
  scope.symbols = s.scope.symbols.copy();
  c.merge_source_declarations(scope.symbols, s.scope.symbols);
  scope.bindings = s.scope.bindings.copy();
  scope.enumerators = s.scope.enumerators.copy();
  scope.macros = s.scope.macros != NULL ? s.scope.macros.copy() : NULL;
  c.sym.statics = c.sym.statics.copy();
  c.sym.binding_facts = c.semantic_binding_facts().copy();
  c.names.counters = c.names.counters.copy();
}

/** Returns whether the transaction's active scope changed its macro map. */
int SymTxn.local_macros_changed(SymTxn s) {
  SymScope *scope = _semantic_scope(s.compiler.sym, s.scope_index);
  Map before = s.scope.macros, after = scope.macros;
  if (before == NULL || after == NULL)
    return (void *) before != (void *) after;
  return !before.equal(after);
}

// commit and rollback

/** Publishes an active semantic transaction and makes rollback a no-op. */
void SymTxn.commit(SymTxn s) {
  if (!s || !s.active) return;
  Compiler c = s.compiler;
  SymScope *scope = _semantic_scope(c.sym, s.scope_index);
  SymScope staged = *scope;
  /* Restore the original map identities before merging staged rows. Code
     holding a borrowed scope map must observe a committed expansion. */
  *scope = s.scope;
  _merge_scope(c, scope, staged);
  if (s.extended) s._commit_effects();
  s.active = 0;
}

static void _merge_scope(Compiler c, SymScope *scope, SymScope staged) {
  scope.symbols.merge(staged.symbols);
  c.merge_source_declarations(scope.symbols, staged.symbols);
  scope.bindings.merge(staged.bindings);
  scope.enumerators.merge(staged.enumerators);
  if (staged.macros == NULL) return;
  if (scope.macros == NULL) scope.macros = {};
  scope.macros.merge(staged.macros);
}

static void SymTxn._commit_effects(SymTxn s) {
  Compiler c = s.compiler;
  Map adapters = c.names.adapters;
  c.names.adapters = s.adapters;
  s.adapters.merge(adapters);
  foreach (List row, s.base_bindings.list()) {
    SymScope *base = _semantic_scope(c.sym, row.car());
    Map staged = base.bindings, original = row.cadr();
    base.bindings = original;
    original.merge(staged);
  }
}

/** Commits an active transaction, retaining the original semantic-map owners.
    The caller may then release the transaction's construction scope.
    Source-fact collection must be disabled: its records retain staged maps.
    Parsing and evaluation must allocate outside that temporary scope.
*/
void SymTxn.commit_transient(SymTxn s) {
  Compiler c = s.compiler;
  Map statics = c.sym.statics, facts = c.semantic_binding_facts();
  Map counters = c.names.counters;
  s.commit();
  c.sym.statics = s.statics;
  c.sym.binding_facts = s.binding_facts;
  c.names.counters = s.counters;
  _replace_map(s.statics, statics);
  _replace_map(s.binding_facts, facts);
  _replace_map(s.counters, counters);
}

/* Copy the staged state back without retaining its container. Deletions
   matter: a declaration can remove an earlier file-static designation. */
static void _replace_map(Map original, Map staged) {
  Array keys = $auto(original.keys());
  foreach (Var key, keys) if (!staged.contains(key)) original.del(key);
  original.merge(staged);
}

/** Restores every semantic value captured by an active transaction. */
void SymTxn.rollback(SymTxn s) {
  if (!s || !s.active) return;
  Compiler c = s.compiler;
  s._restore();
  if (s.extended) s._restore_effects();
  if (c.source_facts && c.source_primary) s._restore_sources();
  s.active = 0;
}

static void SymTxn._restore(SymTxn s) {
  Compiler c = s.compiler;
  SymScope *scope = _semantic_scope(c.sym, s.scope_index);
  *scope = s.scope;
  c.sym.statics = s.statics;
  c.sym.binding_facts = s.binding_facts;
  c.names.next_binding = s.next_binding;
  c.sym.local_macro_names = s.local_macro_names;
  c.names.counters = s.counters;
  c.init_fn = s.initializer_name;
  c.fini_fn = s.shutdown_name;
}

static void SymTxn._restore_effects(SymTxn s) {
  Compiler c = s.compiler;
  c.names.adapters = s.adapters;
  foreach (List row, s.base_bindings.list())
    _semantic_scope(c.sym, row.car()).bindings = row.cadr();
  c.early_decls.resize(s.early_count);
  c.inits.resize(s.init_count);
  c.origins.resize(s.origin_count);
  c.origin = s.origin;
  c.needs_exception = s.needs_exception;
}

static void SymTxn._restore_sources(SymTxn s) {
  Compiler c = s.compiler;
  c.source_occurrences.resize(s.source_occurrences);
  foreach (Var key, c.source_definitions.keys().list())
    c.source_definitions.del(key);
  c.source_definitions.merge(s.source_definitions);
}

// typedef resolution

/* Longest typedef chain any legitimate source may hand to the resolver:
   a mutually recursive pair (typedef A B; typedef B A;) otherwise walks
   forever.  A bound rather than a visited set, because is_var_type
   resolves on nearly every converted expression and that hot path
   must not allocate.

   One user typedef costs two resolver hops, the name node ("B") and then
   the (typedef "B") node it maps to, so the raw recursion budget is
   twice the user-visible chain bound.  The budget counts every hop
   rather than only name hops so that the walk still terminates if a
   typedef node is ever mapped straight onto another typedef node. */
#define RESOLVE_KEY_MAX_TYPEDEFS 64
#define RESOLVE_KEY_MAX_HOPS (2 * RESOLVE_KEY_MAX_TYPEDEFS)

/** Resolves a canonical typedef key to the end of its declared chain. */
Type Sym.resolve_key(Sym s, Type key) {
  if (!key) return key;
  key = key.canonicalize();
  return _resolve_key_helper(s, key, NULL, key, 0);
}

/* Resolve a typedef chain, optionally stopping at a semantic type
   identity. origin is the type the caller asked about, kept only so an
   over-budget walk can name it instead of some mid-chain link. */
static Type _resolve_key_helper(
  Sym s, Type key, Type stop, Type origin, int hops) {
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  if (stop && key == stop) return key;
  if (key.is_typedef_name() || key.is_typedef()) {
    Type type = _typedef_target(s, key);
    if (type) return _resolve_key_helper(s, type, stop, origin, hops + 1);
  }
  match (key) case %((!set ?kind (!or struct union))
      (binding ? ?spelling)):
    if (!s.field_order(key)) return %($kind $spelling);
  return key;
}

/* The resolver cannot tell a true cycle from an absurdly long chain, so the
   diagnostic states only what it can determine. `typedef Color Color;` is
   legal C; it binds ("Color") to (typedef "Color") and back, so cycles are
   real. */
static void _typedef_budget_error(Sym s, Type origin) {
  String message =
    %"typedef chain too deep (possible cycle) resolving ${origin.repr()}";
  s.compiler.report_error(<type>, message, NULL, NULL);
}

/* Semantic types contain no local aliases. A retained file type's spelling
   must keep its meaning when an inner declaration shadows that spelling. */
static Type _typedef_target(Sym s, Type key) {
  for (int i = s.base_scopes - 1; i >= 0; i--) {
    Var target;
    if (_semantic_scope(s, i).symbols.try_get(key, target)) return target;
  }
  return NULL;
}

/** Resolves one typedef hop and counts against the shared cycle budget.

    `hops` is an in-out counter initialized by the caller for the whole walk.
    Returns `NULL` for an unresolved link. The shared budget turns a cycle
    into the same diagnostic as full-chain resolution.
*/
Type Sym.next_typedef(Sym s, Type type, int &hops) {
  if (++hops > RESOLVE_KEY_MAX_HOPS) {
    _typedef_budget_error(s, type);
    return NULL;
  }
  return type.is_typedef_name() || type.is_typedef()
       ? _typedef_target(s, type) : s.get(type);
}

/** Resolves a typedef name through the base scopes only, ignoring local
    typedefs, or returns NULL when the base scopes do not declare it. */
Type Sym.resolve_base_type(Sym s, Type key) {
  Type type = _typedef_target(s, key);
  for (int hops = 0; type && hops < RESOLVE_KEY_MAX_HOPS; hops++) {
    Type next = _typedef_target(s, type);
    if (!next) break;
    type = next;
  }
  return type;
}

/** Resolves typedef bases while retaining every declarator qualifier. */
Type Sym.normalize_declared_type(Sym s, Type type) =>
  type ? _normalize_declared_type(s, type, type, 0) : NULL;

static Type _normalize_declared_type(
  Sym s, Type type, Type origin, int hops) {
  type = type.declared();
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  Type next = _typedef_base_step(s, type);
  return next ? _normalize_declared_type(s, next, origin, hops + 1) : type;
}

static Type _typedef_base_step(Sym s, Type type) {
  Type base = type.base_type();
  if (!base || (!base.is_typedef_name() && !base.is_typedef())) return NULL;
  Type next = _typedef_target(s, base);
  if (!next) next = _builtin_typedef_scalar(base);
  return next ? _replace_type_base(type, base, next) : NULL;
}

static Type _replace_type_base(Type type, Type base, Type replacement) {
  if (type === base) return replacement;
  if (!type) return type;
  return cons(type.car(), _replace_type_base(type.cdr(), base, replacement));
}

// local and builtin types

/** Resolves a block-local typedef to the type saved at its declaration.
    File-scope names retain their semantic identity. Local alias definitions
    are resolved before they are installed, so one lookup crosses the whole
    local chain without consulting names shadowed since its declaration.
*/
Type Sym.local_type(Sym s, Type type) {
  Type base = type.base_type();
  if (base.is_aggregate_tag() && base.cadr() is <string>)
    return _local_tag(s, type, base);
  return base.is_bare_typedef_name() ? _local_alias(s, type, base) : type;
}

// A local tag resolves to the binding of its nearest declaration.
static Type _local_tag(Sym s, Type type, Type base) {
  for (int i = s.scopes.len() - 1; i >= s.base_scopes; i--) {
    SymScope *scope = _semantic_scope(s, i);
    Var binding;
    if (scope.bindings.try_get(base, binding))
      return _replace_type_base(type, base, %(${base.car()} $binding));
  }
  return type;
}

// A local typedef name resolves to the target saved beside its marker.
static Type _local_alias(Sym s, Type type, Type base) {
  for (int i = s.scopes.len() - 1; i >= s.base_scopes; i--) {
    Map symbols = _semantic_scope(s, i).symbols;
    Var marker;
    if (!symbols.try_get(base, marker)) continue;
    Type declared = marker;
    if (!declared.is_typedef()) return type;
    Var target;
    if (!symbols.try_get(declared, target)) return type;
    return _replace_type_base(type, base, target);
  }
  return type;
}

/** Resolves a numeric typedef without reducing semantic object types.

    Returns `NULL` when resolution yields neither a numeric type nor a
    recognized builtin numeric typedef.
*/
Type Sym.resolve_numeric_type(Sym s, Type type) {
  Type scalar = type.scalar();
  if (scalar) return scalar;
  Type resolved = s.resolve_key(type);
  if (resolved.is_number()) return resolved;
  return _builtin_typedef_scalar(resolved);
}

/* Angle-included system typedefs have no collected binding. These canonical
   forms match Type.scalar and are consulted only after source typedef
   resolution, so a source declaration wins. A 64-bit or pointer-width name
   maps to long where long has that width, retaining the native long Var
   identity, and to long long on a host such as LLP64 Windows where it does
   not.

   The labels are encoded Symbols, not the C spellings, and the subject is
   `name.symbol()`, the same encoding applied to the source identifier.
   A C name that outruns the Symbol capacity therefore appears here in the
   form it encodes to: `size_t` is `<size-t>`, since the 5-bit alphabet
   folds the separator, and `uint16_t` is `<uint16_>`, since a digit forces
   the seven-byte form. `uint8_t` and `int16_t` fit and keep their
   spelling. */
static Type _builtin_typedef_scalar(Type key) {
  if (!key.is_bare_typedef_name()) return NULL;
  String name = key.car();
  switch (name.symbol()) {
    case <u8>: case <uint8_t>: return %(unsigned char);
    case <i8>: case <int8_t>: return %(signed char);
    case <u16>: case <uint16_>: return %(unsigned short);
    case <i16>: case <int16_t>: return %(short);
    case <u32>: case <uint32_>: return %(unsigned);
    case <i32>: case <int32_t>: case <wchar-t>: return %(int);
    case <u64>: case <uint64_>:
      return sizeof(long) == 8 ? %(unsigned long) : %(unsigned long long);
    case <uintptr-t>: case <size-t>:
      return sizeof(long) == sizeof(void *)
           ? %(unsigned long) : %(unsigned long long);
    case <i64>: case <int64_t>:
      return sizeof(long) == 8 ? %(long) : %(long long);
    case <intptr-t>: case <ptrdiff-t>: case <ssize-t>:
      return sizeof(long) == sizeof(void *) ? %(long) : %(long long);
    case <off-t>: case <time-t>: return %(long);
    case <u128>: return %(unsigned long long);
    case <i128>: return %(long long);
    case <f32>: return %(float);
    case <f64>: return %(double);
    case <f128>: return %(long double);
  }
  return NULL;
}

// value types

/** Returns a type's `Var` tag and optionally stores its resolved type.

    `resolved` receives the final type even when the result is zero because no
    `Var` tag is registered. A null input stores `NULL` and returns zero.
*/
Symbol Sym.var_tag_for_type(Sym s, Type type, Type &?resolved) {
  if (!type) {
    if (resolved) resolved = NULL;
    return 0;
  }
  Type origin = type.canonicalize();
  return _var_tag_for_type_helper(s, origin, origin, resolved, 0);
}

static Symbol _var_tag_for_type_helper(
  Sym s, Type type, Type origin, Type &?resolved, int hops) {
  type = type.canonicalize();
  Symbol tag = type.var_tag();
  if (tag) {
    if (resolved) resolved = type;
    return tag;
  }
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(s, origin);
  Type next = _typedef_base_step(s, type);
  if (next)
    return _var_tag_for_type_helper(s, next, origin, resolved, hops + 1);
  if (resolved) resolved = type;
  return 0;
}

/** Reports whether `type` reaches the named `Var` value type. */
int Sym.is_var_type(Sym s, Type type) => s.is_named_value_type(type, "Var");

/** Reports whether `type` reaches the named `String` value type. */
int Sym.is_string_type(Sym s, Type type) =>
  s.is_named_value_type(type, "String");

/** Reports whether `type` reaches the named `Array` value type. */
int Sym.is_array_type(Sym s, Type type) =>
  s.is_named_value_type(type, "Array");

/** Reports whether `type` reaches the named `Map` value type. */
int Sym.is_map_type(Sym s, Type type) => s.is_named_value_type(type, "Map");

/** Reports whether `type` reaches a named value type before its definition. */
int Sym.is_named_value_type(Sym s, Type type, String name) {
  // Stop at the named type instead of resolving through its typedef.
  if (!type || !name) return 0;
  Type wanted = %($name), origin = type.canonicalize();
  type = _resolve_key_helper(s, origin, wanted, origin, 0);
  return type == wanted;
}

// aggregate fields

/** Returns an aggregate field's declared type, or `NULL`.
    A member of an anonymous struct or union belongs to its enclosing
    aggregate in C, so unnamed rows are searched the way a designated
    initializer already reaches them.
*/
Type Sym.lookup_field(Sym s, Type type, List field) {
  type = s.resolve_key(type);
  if (!type || !type.is_aggregate_tag()) return NULL;
  Type found = s.get(%( @type @field ));
  if (found) return found;
  foreach (List row, s.field_order(type).cdr()) {
    Type member = row.cadr();
    if (row.car().truth() || !s.resolve_key(member).is_aggregate())
      continue;
    found = s.lookup_field(member, field);
    if (found) return found;
  }
  return NULL;
}

/** Records declaration AST fields in source order after binding finishes.

    `Field` types already use member keys. Unnamed rows retain their type
    and an empty name so initializer traversal preserves anonymous subobjects.
*/
void Sym.declare_field_order(Sym s, Type type, List fields) {
  Array rows = [];
  foreach (List declaration, fields) {
    while (declaration.car() == <at>) declaration = declaration.caddr();
    if (declaration.car() == <c-assert>) continue;
    List bindings = declaration.caddr();
    foreach (List declarator, bindings.cdr())
      rows.push(_field_row(s, type, declaration, declarator));
  }
  s.set(%(@type "field-order"), %(fields @{rows.list_free()}));
}

static List _field_row(Sym s, Type type, List declaration, List declarator) {
  String name = binding_identity_spelling(declarator.cadr());
  Type declared = name ? s.get(%(@type $name))
    : %(declare ${declaration.cadr()} (bindings $declarator))
      .type_from_ast().declared();
  return %($name $declared);
}

/** Returns recorded fields in source order, or `NULL`. */
List Sym.field_order(Sym s, Type type) => s.get(%(@type "field-order"));

/** Marks one named aggregate field as a delegate. */
void Sym.declare_delegate_field(Sym s, Type aggregate, String name) {
  s.set(%(@aggregate delegate $name), %(delegate));
}

/** Resolves typedefs or one pointer layer to an aggregate tag, or `NULL`. */
Type Sym.delegate_aggregate(Sym s, Type type) {
  type = type.canonicalize();
  int hops = 0;
  while (type && !type.is_aggregate_tag()) {
    if (type.is_pointer()) {
      type = s.resolve_key(type.dereference());
      break;
    }
    type = s.next_typedef(type, hops);
  }
  return type && type.is_aggregate_tag() ? type : NULL;
}

// binding facts

/** Returns the current borrowed semantic-facts map indexed by binding.

    A semantic transaction may replace this map, so reacquire it afterwards.
*/
Map Compiler.semantic_binding_facts(Compiler c) => c.sym.binding_facts;

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
static List _fact(Compiler c, List key) {
  Var stored;
  return c.semantic_binding_facts().try_get(key, stored) ? stored : NULL;
}

/** Returns the optional references proven present in this lexical path. */
List Compiler.present_references(Compiler c) =>
  _fact(c, %(present-references));

/** Records a nonnull optional parameter for the current lexical path. */
void Compiler.mark_reference_present(Compiler c, List binding) {
  List present = c.present_references();
  if (!(binding in present))
    c.semantic_binding_facts()[%(present-references)] = cons(binding, present);
}

/** Restores the optional-reference facts saved before a lexical path. */
void Compiler.restore_reference_presence(Compiler c, List before) {
  if (before === c.present_references()) return;
  if (before) c.semantic_binding_facts()[%(present-references)] = before;
  else c.semantic_binding_facts().del(%(present-references));
}

/** Returns the optional-reference parameter tested by `condition`, or NULL.
    `truth` is set to whether the condition's true arm proves that the caller
    supplied an object. Only a direct truth or null test proves presence.
*/
List Compiler.optional_reference_test(
  Compiler c, List condition, int &truth) {
  match (condition) {
    case %(expr ? (parens ?inner)):
      return c.optional_reference_test(inner, truth);
    case %(expr ? (op ! ?operand)): {
      truth = !truth;
      return c.optional_reference_test(operand, truth);
    }
    case %(expr ? (op (!set ?op (!or == !=)) ?left ?right)):
      return _null_comparison(c, op, left, right, truth);
  }
  match (condition)
    case %(expr (opt-ref *) (ident ?binding)):
      if (%(optional-reference-param $binding) in
          c.semantic_binding_facts()) return binding;
  return NULL;
}

/* A comparison with a null literal tests the other operand; its true arm
   proves presence for `!=`. */
static List _null_comparison(
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
    case %(expr ? (parens ?inner)): return _null_literal(inner);
    case %(expr ? (ident (binding ? "NULL"))): return 1;
    case %(expr ? (literal ? "0")): return 1;
  }
  return 0;
}

/** Returns whether `arm` ends with a return or non-returning raise. */
int reference_guard_exits(List arm) {
  if (Ast.never_returns(arm)) return 1;
  match (arm) {
    case %(return *): return 1;
    case %(at ? ?body): return reference_guard_exits(body);
    case %(block *items):
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
    the file initializer's three stages.
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
    List cached = _cache_literal_list(c, value);
    return c.cache(%( var (expr ("List") (expr ("List") $cached)) ));
  }
  if (value is <string>) {
    List literal = %(expr ("String") (literal ("String") $value));
    List cached = c.cache(%(string $literal));
    return c.cache(%(var (expr ("String") $cached)));
  }
  if (value.is_integer() || value.is_floating())
    return _cache_boxed(c, c.meta_value_expression(NULL, value, NULL));
  if (value is <lsym>)
    return _cache_boxed(
      c, %(expr ("Atom") (literal ("Atom") ${value.str()} $value)));
  if (value is not <symbol>) return NULL;
  String spelling = value.symbol();
  List literal = %(
    expr ("Symbol") (literal ("Symbol") $spelling $value)
  );
  return c.cache(%(var $literal));
}

// A number or atom is cached through its conversion to a `Var`.
static List _cache_boxed(Compiler c, List literal) {
  literal = c.convert_expression(literal, %("Var"));
  return c.cache(%(var $literal));
}

static List _cache_literal_list(Compiler c, List values) {
  Array heads = $auto([]);
  foreach (Var value, values) heads.push(c.cache_literal_var(value));
  List result = %(nil);
  for (int i = (int) heads.len() - 1; i >= 0; i--) {
    List head = heads[i];
    result = c.cache(%(cons $head $result));
  }
  return result;
}

/** Returns a runtime `List` expression for cached compiler-owned syntax.

    `values` may contain nested `List`s, `String`s, integer `Var`s, and
    `Symbol`s.
*/
List Compiler.cache_literal_list(Compiler c, List values) {
  List cached = _cache_literal_list(c, values);
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
  if (head == <expr>) return c.match_pattern_value(ast.last());
  if (head == <var>) return c.match_pattern_value(second);
  if (head == <string>) return c.match_pattern_value(second);
  if (head == <call>) return _call_value(c, second, third);
  if (head == <literal>) return ast.last();
  if (head == <nil>) return %();
  if (head == <cons>) return _cons_value(c, second, third);
  return <x2c-dyn>;
}

/* A converter call has the value it converts, and a case pattern matches
   what its labels match. Any other call is computed. */
static Var _call_value(Compiler c, Var callee, Var args) {
  String converter = _converter_name(callee);
  if (converter == "List_var" || converter == "Symbol_var")
    match (args) case %(args ?argument):
      return c.match_pattern_value(argument);
  if (converter == "Macro_case_pattern")
    match (args) case %(args ? ?names): {
      List labels = c.match_pattern_value(names);
      return %(!and x2c-dyn @labels);
    }
  return <x2c-dyn>;
}

static Var _cons_value(Compiler c, Var head, Var tail) {
  Var value = c.match_pattern_value(head);
  Var rest = c.match_pattern_value(tail);
  if (rest is not <list>) return <x2c-dyn>;
  return cons(value, rest);
}

static String _converter_name(Var node) {
  if (node is <string>) return node;
  if (node is not <list>) return NULL;
  List matched = node.list().match(%(expr ? (ident ?binding)));
  if (!matched) return NULL;
  List binding = matched.assoc(<?binding>);
  return binding_identity_spelling(binding);
}

/** Reports whether a recovered pattern value graph is fully static. */
int match_value_is_static(Var value) {
  if (value == <x2c-dyn>) return 0;
  if (value is not <list>) return 1;
  foreach (Var part, value.list())
    if (!match_value_is_static(part)) return 0;
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
  Array typed = [];
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
  if (tags) tags = typed.list_free();
  else typed.free();
  return head;
}

/* A typed capture element is `(!is ?name type <tag>)` with a literal tag.
   The runtime matcher canonicalizes `varray` and `vmap`; those spellings
   keep the runtime path rather than repeating that rule here. */
static Symbol _flat_capture_tag(Var element, Var binder) {
  if (element is not <list>) return 0;
  List predicate = element;
  if (predicate.len() != 4) return 0;
  Var (op, named, keyword, tag) = predicate;
  if (op != <!is> || named != binder || keyword != <type>) return 0;
  if (tag is not <symbol> || tag == <x2c-dyn> ||
      tag == <varray> || tag == <vmap>)
    return 0;
  return tag;
}

// match binders

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

// diagnostics routing

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

/** Moves collected child reports into the caller's store without re-emitting.
    Shared stores already contain their entries. The child's separate store
    remains configured and empty after its reports have been transferred.
*/
void Compiler.take_diagnostics(Compiler c, Compiler child) {
  Diagnostics target = c.diagnostics, source = child.diagnostics;
  if (target == source) return;
  foreach (Var entry, source.entries) target.entries.push(entry);
  target.count += source.count;
  target.limit_notified |= source.limit_notified;
  source.reset();
}

/** Retains a child's final diagnostics and closes its owned Lisp session. */
void Compiler.close_child(Compiler c, Compiler child) {
  c.take_diagnostics(child);
  child.free_lisp();
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
    case %(macrodef *rows): return _declaration_macro(c, rows, 0);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source ${_declaration_path(path, 0)} $begin $end)
        ${c.freeze_declaration_syntax(node)});
    case %(at ?(int origin) ?node): return _freeze_origin(c, origin, node);
  }
  return _freeze_rows(c, syntax);
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
static List _freeze_origin(Compiler c, int origin, Var node) {
  List location = c.origin_location(origin);
  if (!location) return %(at m-origin ${c.freeze_declaration_syntax(node)});
  return %(declaration-origin ${_declaration_location(location, 0)}
            ${c.freeze_declaration_syntax(node)});
}

// A List whose head is a marker is escaped, so thawing keeps its value.
static List _freeze_rows(Compiler c, List syntax) {
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
    case %(declaration-list *rows): return _thaw_rows(c, rows);
    case %(macrodef *rows): return _declaration_macro(c, rows, 1);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source ${_declaration_path(path, 1)} $begin $end)
        ${c.thaw_declaration_syntax(node)});
    case %(declaration-void): return void;
    case %(declaration-empty-symbol): return (Symbol) 0;
    case %(declaration-atom ?spelling): return Atom.intern(spelling);
    case %(declaration-token ?type ?text ?line ?column ?length ?position):
      return _thaw_token(type, text, line, column, length, position);
    case %(declaration-origin ?location ?node):
      return _thaw_origin(c, location, node);
  }
  return _thaw_rows(c, syntax);
}

static List _thaw_rows(Compiler c, List rows) {
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
static List _thaw_origin(Compiler c, List source, Var node) {
  c.origins.push(
    %(source ${source.assoc(<file>)}
      ${source.assoc(<line>)} ${source.assoc(<column>)}
      ${source.assoc(<length>)} ${source.assoc(<position>)}));
  return %(at ${c.origins.len()} ${c.thaw_declaration_syntax(node)});
}

static List _declaration_macro(Compiler c, List rows, int thaw) {
  Array out = [];
  foreach (List row, rows) {
    match (row) {
      case %(origin ?location):
        row = %(origin ${_declaration_location(location, thaw)});
      default:
        row = thaw ? c.thaw_declaration_syntax(row)
                   : c.freeze_declaration_syntax(row);
    }
    out.push(row);
  }
  return %(macrodef @{out.list_free()});
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

// declaration production

/** Queues a source Lisp form until declaration production needs its state.
    Files without declaration producers keep ordinary full-parse evaluation. */
void Compiler.queue_declaration_effect(
  Compiler c, String form, Token first, Token after) {
  List key = _declaration_source_key(c, first);
  String context = c.import_stack.len() ? c.import_stack[-1] : c.filename;
  c.declaration_effects = cons(
    %($key ${after.pos} $form ${c.freeze_declaration_syntax(first)} $context),
    c.declaration_effects);
}

static List _declaration_source_key(Compiler c, Token token) {
  String path = home_portable_path(Path.absolute(c.filename));
  return %("source-node" (declaration $path ${token.pos}));
}

/** Runs pending effects for declaration production or CPP macro evaluation. */
void Compiler.run_declaration_effects(Compiler c) {
  List effects = c.declaration_effects.reverse();
  c.declaration_effects = NULL;
  foreach (List effect, effects) {
    (List key, int end, String form, Var site, String context) = effect;
    $let(c.filename, _effect_file(c, key)) {
      c.import_stack.push(context);
      defer c.import_stack.take_last();
      Token token = c.thaw_declaration_syntax(site);
      c.evaluate_declaration_effect(form, token);
      if (c.collect_protocols)
        c.sym.set(key, %(declaration-source $end (declaration-bundle (rows))));
    }
  }
}

// An effect runs in the file whose declaration queued it.
static String _effect_file(Compiler c, List key) {
  match (key)
    case %("source-node" (declaration ?path ?)):
      return _declaration_path(path, 1);
  return c.filename;
}

/** Expands a file-scope unit macro and retains its declarations for collection.
    Its private helpers remain available to later invocations. Generated-name
    counters are restored when the full parse must expand it again.
*/
void Compiler.collect_unit_macro(Compiler c) {
  Map counters = c.names.counters;
  c.names.counters = counters.copy();
  SymTxn transaction = c.begin_semantic_transaction();
  Token first = c.token;
  List syntax = c.parse_top_level();
  int retained = _retain_bundle(c, syntax, first, c.token);
  transaction.commit();
  /* The full parse expands this unit again. Keep the declarations needed
     by later shallow invocations, but do not count its generated names
     twice. */
  if (!retained) c.names.counters = counters;
}

/* The owning source records one declaration production, including its exact
   token span. Full parsing consumes that production instead of invoking its
   compile-time producer again. Ordinary Unit macros retain their old path. */
static int _retain_bundle(Compiler c, List syntax, Token first, Token after) {
  match (syntax) {
    case %(seq ?only): return _retain_bundle(c, only, first, after);
    case %(declaration-bundle (rows *)): {
      List frozen = c.freeze_declaration_syntax(syntax);
      c.sym.set(
        _declaration_source_key(c, first),
        %(declaration-source ${after.pos} $frozen));
      return 1;
    }
  }
  return 0;
}

static List _replay_bundle(Compiler c) {
  List source = c.sym.get(_declaration_source_key(c, c.token));
  match (source)
    case %(declaration-source ?(int end) ?syntax): {
      List thawed = c.thaw_declaration_syntax(syntax);
      List bound = c.bind_syntax(thawed, AST_UNIT, NULL);
      while (c.peek(0) != <eof> && c.token.pos < end) c.next();
      return bound;
    }
  return NULL;
}

/* declaration defaults

   A declaration producer can offer defaults: functions that bind only when
   no other declaration takes their name, and constructors that forward to
   a parent's constructor. The owning file selects them after all its
   segments. */

/* One selection of a file's defaults. `shadow` binds them over the file's
   collected symbols. `sources` holds one `(declarations key end rows)`
   entry per production, and `pending` the children whose forwarded
   constructors wait for their parent's constructor. */
typedef struct Defaults {
  Compiler shadow, Array parts, sources;
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
  _prepare_shadow(shadow, c, path, symbols);
  Array sources = [];
  Map pending = {};
  Defaults d = {
    .shadow = shadow, .parts = parts, .sources = sources,
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
static void _prepare_shadow(
  Compiler shadow, Compiler owner, String path, Map symbols) {
  shadow.filename = path;
  shadow.macro_lisp = owner.macro_lisp;
  shadow.borrowed_lisp = shadow.macro_lisp != NULL;
  shadow.share_meta_group(owner);
  shadow.sym._reset_overlay(symbols, {});
  shadow.rebuild_protocols(symbols);
  shadow.conforms = {};
  shadow.shallow = 1;
  shadow.declaration_projection = 1;
}

// A part's productions run in source order.
static void Defaults.produce(Defaults *d, Map declarations) {
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
        rows = d.shadow.thaw_declaration_syntax(rows);
        Array produced = [];
        d.shadow._produce(rows, produced);
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
          c._produce(_generated_rows(c, callback, arguments), selected);
        continue;
      }
    selected.push(row);
  }
}

// A recipe's rows: the children of a sequence or bundle, or its one node.
static List _generated_rows(Compiler c, Var callback, Var arguments) {
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
static void Defaults.select(Defaults *d) {
  for (size_t index = 0; index < d.sources.len(); index++) {
    (Map declarations, Var key, Var end, List rows) = d.sources[index];
    List selected = d._select_rows(rows);
    foreach (List row, selected)
      match (row)
        case %(declaration-forward ?child *): d.pending[child] = 1;
    d.sources[index] = %($declarations $key $end $selected);
  }
}

static List Defaults._select_rows(Defaults *d, List rows) {
  Compiler c = d.shadow;
  Array selected = [];
  foreach (List row, rows) {
    match (row)
      case %(declaration-default ?function ?construction ?privacy): {
        $let(c.macro_stack, c.thaw_declaration_syntax(construction))
        $let(c.source_private, privacy) {
          Var syntax = d._unless_taken(function);
          if (syntax is not void) selected.push(_bind_default(c, syntax));
        }
        continue;
      }
    selected.push(row);
  }
  return selected.list_free();
}

/* Returns the function to bind for a default, named through its macro
   slot, or void when a declaration already takes its name. */
static Var Defaults._unless_taken(Defaults *d, List syntax) {
  match (syntax)
    case %(function ?return_type (bind ?name ?modifiers) ?body): {
      name = d.shadow.evaluate_macro_slot(name);
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
static int Defaults._taken(Defaults *d, String spelling) {
  Compiler c = d.shadow;
  List key = %($spelling);
  Type declared = c.sym.get(key);
  if (!declared) return 0;
  if (!declared.is_function() || spelling in d.definitions ||
      spelling in c.fn_defs || %(function $spelling) in c.sym.file_statics())
    return 1;
  foreach (Var part, d.parts)
    if (part is <map> && key in part.map()) return 0;
  return 1;
}

static List _bind_default(Compiler c, List syntax) {
  if (c.source_private)
    match (syntax)
      case %(function ?type ?declarator ?body):
        if (!type.type().is_static())
          syntax = %(function (static @type) $declarator $body);
  return c.bind_syntax(syntax, AST_UNIT, NULL);
}

/* Forwarded constructors bind as their parents' constructors complete; a
   round that completes none leaves a parent that never will. */
static void Defaults.forward(Defaults *d) {
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
      d.shadow.report_error(
        <type>,
        "a forwarded class constructor has no completed parent constructor",
        d.shadow.token, NULL);
  }
}

static List Defaults._forward_rows(Defaults *d, List rows, int &remaining) {
  Array selected = [];
  foreach (List row, rows) {
    match (row)
      case %(declaration-forward ?child ?parent ?member ?fallback ?privacy): {
        List bound = NULL;
        $let(d.shadow.source_private, privacy)
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
  Defaults *d, Type child, Type parent, String member, List fallback) {
  Compiler c = d.shadow;
  String name = %"${child.car()}_$member";
  if (c.sym.get(%($name))) return %(seq);
  List method = c.resolve_postfix_member(parent, %($member), <.>, 1);
  if (!method) {
    if (parent in d.pending) return NULL;
    return fallback ? _bind_default(c, fallback.car()) : NULL;
  }
  List binding = NULL, Type signature = NULL;
  match (method)
    case %(method ?target ?type): {
      binding = target;
      signature = type;
    }
  if (!signature) return NULL;
  return _bind_default(c, _forwarder(c, name, child, binding, signature));
}

// The forwarding constructor passes each argument on and casts the result.
static List _forwarder(
  Compiler c, String name, Type child, List binding, Type signature) {
  List types = NULL;
  match (signature) case %((func ?parameters) *): types = parameters;
  Array parameters = [], arguments = [];
  int index = 0;
  foreach (Var type, types) {
    if (type == <...>)
      c.report_error(
        <type>, %"'$name' requires an explicit variadic constructor",
        c.token, NULL);
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
static void Defaults.store(Defaults *d, Map symbols) {
  foreach (List source, d.sources) {
    (Map declarations, Var key, Var end, List rows) = source;
    declarations[key] = d.shadow.freeze_declaration_syntax(
      %(declaration-source $end (declaration-bundle (rows @rows))));
    symbols[key] = declarations[key];
  }
}

// shallow collection

/** Collects file-scope declarations into `globals` without parsing bodies. */
void Compiler.shallow_parse(Compiler c, Map globals) {
  c.macros = {};
  c.kw_aliases = {};
  c.kw_seen = {};
  c.import_stack.clear();
  c.sym.reset(globals);
  c.install_builtin_macros();
  _shallow_parse_loop(c);
  _check_unmatched_braces(c);
}

/** Collects declarations with reads over `base` then `overlay`.

    Writes go to `overlay`, which captures exactly what this translation
    contributes above `base`.
*/
void Compiler.shallow_parse_overlay(Compiler c, Map base, Map overlay) {
  if (c.macros == NULL || !c.macros.len()) _start_macros(c);
  c.sym._reset_overlay(base, overlay);
  c.install_builtin_macros();
  _shallow_parse_loop(c);
  // Only linkage groups remain open; a later segment of the file closes them.
  c.open_linkage += c.braces.len();
}

// A unit with no macros yet starts its macro, keyword, and import state.
static void _start_macros(Compiler c) {
  c.macros = {};
  if (c.kw_aliases == NULL) c.kw_aliases = {};
  if (c.kw_seen == NULL) c.kw_seen = {};
  c.imports = {};
  c.import_stack.clear();
}

static void _shallow_parse_loop(Compiler c) {
  c.rebuild_protocols(NULL);
  c.conforms = {};
  c.shallow = 1;
  c.braces.clear();
  while (c.peek(0) != <eof>) {
    Token start = c.token;
    (void) c.parse_top_level_mode(1);
    _debug_tokens(start, c.token);
  }
  /* Definitions after the last declaration, as before an include, still
     define macros for the segments that follow. */
  foreach (List directive, c.leading_preproc())
    _note_object_macro(c, directive.cadr());
  c.shallow = 0;
}

static void _debug_tokens(Token start, Token end) {
  if (!log_should_log(<debug>, <tokenizer>)) return;
  for (Token tok = start; tok < end; tok++)
    if (tok.type != <space> && tok.type != <comment> && tok.type != <preproc>)
      log_debug(
        <tokenizer>, %(
        (func "tokenize")
        (type ${tok.type})
        (text ${tok.text})
        (line ${tok.line})
        (col  ${tok.col})
      ));
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
  /* Collection records the runtime function a `meta` marker precedes, and
     the native binding a bodyless or `native` marker advertises; the
     compile-time form is installed by the full parse. */
  c.record_declaration_visibility(declaration);
  /* Lexical privacy also marks a name in Sym.statics, so a static function
     is marked again as `(function name)`. File collection reads that key to
     keep the function out of what a private region publishes. */
  match (declaration)
    case %(declare ?type (bindings (bind ?binding ((fnmod *) *)))):
      if (type.type().is_static())
        c.sym.mark_static(%(function ${binding_identity_spelling(binding)}));
  if (c.peek(0) == <"{"> || c.peek(0) == <"%{"> || c._at_function_arrow())
    _skip_body(c, declaration, meta, native);
  else if (c.peek(0) == <;>) {
    if (meta) c.record_native_meta_effect(declaration, meta);
    c.next();
  }
  else c.next();
}

static void _skip_body(Compiler c, List declaration, Token meta, int native) {
  if (native) c.record_native_meta_effect(declaration, meta);
  match (declaration)
    case %(declare ? (bindings (bind ?binding ?))):
      _note_function_body(c, declaration.type_from_ast(), binding);
  if (c._at_function_arrow()) {
    c.next();
    c.next();
    c._skip_shallow_expression(0);
    c.expect(<;>);
  }
  else _shallow_block(c);
}

// Remember the spelling of one function body found while collecting `.x`.
static void _note_function_body(Compiler c, Type type, List binding) {
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

static void _shallow_block(Compiler c) {
  c.next();
  for (Symbol peek = c.peek(0); peek != <"}">; peek = c.peek(0)) {
    if (peek == <eof>)
      c.report_error(<parse>, "unexpected end of file", c.token, NULL);
    if (peek == <"{"> || peek == <"%{"> || peek == <"${"> || peek == <"@{">)
      _shallow_block(c);
    else c.next();
  }
  c.expect(<"}">);
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
    conflict = _parse_forms(c, nodes);
  if (conflict) {
    c.token = conflict;
    _report_script_statement(c);
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
  c.replay_included_package_imports(globs, c.filename, {});
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
static Token _parse_forms(Compiler c, Array nodes) {
  _append_preproc(c, nodes);
  Array statements = [];
  FullParse p = {
    .c = c, .nodes = nodes, .statements = statements,
    .hoisting = c.script && !c.script.defines_main};
  loop {
    while (c.peek(0) != <eof>) if (!p.form()) break;
    if (!p.runs) return NULL;
    Token tokens = c.tokenizer.tokens;
    if ("main" in c.fn_defs) return tokens + p.first;
    _push_conditionals(c, statements, p.gap, c.token - tokens);
    _append_script_main(c, statements);
    p.hoisting = p.runs = 0;
  }
}

/* Parses one form, or skips a failed one whole. Returns 0 when the parse
   stops: the error limit is reached, or the skip reached the end. */
static int FullParse.form(FullParse *p) {
  Compiler c = p.c;
  Token start = c.token;
  int braces = c.braces.len();
  try {
    p.parse(start);
  }
  catch %(malformed (category ?category) *): {
    (void) category;
    if (c.diagnostics.reached_limit()) return 0;
    _sync_top_level(c, start, braces);
    p.gap = _end_index(c, c.tokenizer.tokens);
    _append_preproc(c, p.nodes);
    return c.peek(0) != <eof>;
  }
  return 1;
}

static void FullParse.parse(FullParse *p, Token start) {
  Compiler c = p.c;
  Token tokens = c.tokenizer.tokens;
  int begin = start - tokens;
  if (p.hoisting) _push_conditionals(c, p.statements, p.gap, begin);
  if (p.hoisting && c.script_statement_starts()) p.hoist(begin, tokens);
  else p.top_level(begin, tokens);
  p.gap = _end_index(c, tokens);
  _append_preproc(c, p.nodes);
  _debug_tokens(start, c.token);
}

// A script statement joins the runs that `main` executes.
static void FullParse.hoist(FullParse *p, int begin, Token tokens) {
  p.c.skip_script_statement();
  int end = _end_index(p.c, tokens);
  p.statements.push(begin);
  p.statements.push(end);
  if (!p.runs++) p.first = begin;
}

// A retained declaration bundle replays; any other form parses.
static void FullParse.top_level(FullParse *p, int begin, Token tokens) {
  Compiler c = p.c;
  _reject_statement(c);
  Ast node = _replay_bundle(c);
  if (!node) node = c.parse_top_level();
  int end = _end_index(c, tokens);
  if (node && node.car() == <seq>)
    foreach (List item, node.cdr()) p.add(item, begin, end);
  else if (node) p.add(node, begin, end);
}

static void FullParse.add(FullParse *p, List node, int begin, int end) {
  _record_top_level(p.c, node);
  _record_span(p.c, node, begin, end);
  p.nodes.push(node);
}

// The index just past the last non-trivia token before the cursor.
static long _end_index(Compiler c, Token tokens) =>
  _skip_backward(c.token - 1, tokens) + 1 - tokens;

/* The directives before the cursor join the nodes in source order, after
   they update source visibility and the unit's macro names. */
static void _append_preproc(Compiler c, Array nodes) {
  List directives = c.leading_preproc();
  c.update_source_visibility(directives);
  foreach (Var directive, directives) nodes.push(directive);
}

/* A failed declaration is skipped whole from its first token, because a
   report inside a body leaves the cursor where no declaration can start.
   The declaration ends at a `;` outside delimiters, at a closing delimiter
   whose next token begins a later line, such as a function body or a macro
   invocation, or at a `}` that nothing on its line continues. A `struct`
   body continues to its declarators, and a second function body on the
   same line is a second declaration. */
static void _sync_top_level(Compiler c, Token start, int braces) {
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
  _append_meta_definitions(c, nodes);
  c.unit_nodes = NULL;
  List ast = nodes.list_free();
  if (c.script && !c.script.defines_main && !c.error_count())
    _check_script_locals(c, ast);
  _check_unmatched_braces(c);
  if (!c.error_count()) _check_static_inits(c);
  return ast;
}

// script units

/** Skips a collected script statement, or diagnoses one beside `main`.
    Called after top-level directives establish source visibility.
*/
int Compiler.skip_collected_script_statement(Compiler c) {
  if (!c.script) return 0;
  if (!c.script.defines_main && c.script_statement_starts()) {
    c.skip_script_statement();
    return 1;
  }
  _reject_statement(c);
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
static void _reject_statement(Compiler c) {
  if (c.script && c.script.defines_main && c.script_statement_executes())
    _report_script_statement(c);
}

static void _report_script_statement(Compiler c) {
  c.report_error(
    <parse>, "a script that defines main cannot have top-level statements",
    c.token,
    %("move the statement into main, or remove main so the statements run"));
}

/* A file-scope conditional directive also governs the statements it
   surrounds, so a copy of each joins the statement runs in source order and
   the script body keeps the file's conditional structure. */
static void _push_conditionals(
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
static void _append_script_main(Compiler c, Array statements) {
  Token tokens = c.tokenizer.tokens, eof = c.token;
  long kept = _end_index(c, tokens);
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
  c.token = _skip_forward((Token) stream + kept);
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
static void _check_script_locals(Compiler c, List ast) {
  Map locals = _script_locals(ast);
  if (!locals.len()) return;
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? ?(String function)) ?)
           (block *items)):
      if (function != "x2c_script" && function != "main")
        _check_local_uses(c, items, locals);
}

static Map _script_locals(List ast) {
  Map locals = {};
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? "x2c_script") ?) (block *items)):
      foreach (List item, items) match (item)
        case %(at ? (declare ? (bindings *bindings))):
          foreach (List binding, bindings) match (binding)
            case %(!or (bind (binding ? ?(String name)) ?)
                       (op = (bind (binding ? ?(String name)) ?) ?)):
              locals[name] = 1;
  return locals;
}

static void _check_local_uses(Compiler c, List items, Map locals) {
  foreach (List item, items) match (item) case %(at ?origin ?statement):
    foreach (Var name, locals.keys()) {
      Var found;
      List bindings;
      int present = statement.list().try_search(
        %(expr () (ident (binding ? $name))), found, bindings);
      if (!present) continue;
      c.origin = origin;
      c.report_error(
        <type>,
        %"'$name' is declared among the script's statements",
        NULL,
        %("functions cannot see those locals;"
          "declare it static to share it"));
    }
}

// top-level definitions

static void _record_top_level(Compiler c, List node) {
  match (node) {
    case %(declare (!set ?declared (*)) (bindings *bindings)): {
      Type type = declared;
      _record_objects(c, bindings);
      _record_static_object(c, type, bindings);
      _record_prototypes(c, type, bindings);
    }
    case %(function ?return_type
           (!set ?target (bind ?binding *)) ?): {
      List declaration = %(declare $return_type (bindings $target));
      _record_definition(c, declaration.type_from_ast(), binding);
    }
  }
}

/* An initializer makes a file-scope declaration a definition; a tentative
   one may be repeated. */
static void _record_objects(Compiler c, List bindings) {
  foreach (List row, bindings)
    match (row) case %(op = (bind (!set ?binding (binding ? ?)) ?) ?): {
      List key = %(defined $binding);
      Map facts = c.semantic_binding_facts();
      if (key in facts) _report_redefinition(c, "variable", binding);
      facts[key] = 1;
      facts[%(arms $binding)] = c.arms;
    }
}

/* Reports a second definition of one file-scope name, which C rejects,
   when both sit under the same conditional arms. Definitions under
   different arms are not compared. For a variable, whose initializer moves
   into the generated init function, a duplicate under two true conditions
   is therefore not detected, and the later initializer wins. */
static void _report_redefinition(Compiler c, String kind, List binding) {
  Var arms;
  if (!c.semantic_binding_facts().try_get(%(arms $binding), arms) ||
      !List.equal(arms, c.arms))
    return;
  String spelling = binding_identity_spelling(binding);
  c.report_error(
    <type>, %"$kind '$spelling' is already defined in this scope",
    c.token, %("prior definition: '$spelling'"));
}

/* A definition remembers the token range of the top-level form that
   produced it, and whether that form is private, for the definition walk.
   A typedef or declaration may repeat its name, so each statement keys its
   own range. */
static void _record_span(Compiler c, List node, int start, int end) {
  List key = NULL;
  match (node) {
    case %(function ? (bind ?binding ?) ?): key = binding;
    case %(falias (declare ? (bindings (bind ?binding ?))) ?): key = binding;
    case %((!or typedef declare) *): key = node;
  }
  if (key)
    c.semantic_binding_facts()[%(definition-span $key)] =
      %($start $end ${c.source_private > 0});
}

/* function completion

   A function's completion fact records its contract: a prototype, a
   definition, a definition that completed a prototype, or a conflict
   between two prototypes. */

// Record only prototypes reached in positioned full-parse source order.
static void _record_prototypes(Compiler c, Type declared_type, List items) {
  foreach (List target, items)
    match (target)
      case %(bind ?binding ?modifiers): {
        List single = %(declare $declared_type (bindings $target));
        Type type = single.type_from_ast();
        if (type.is_function()) _record_prototype(c, binding, type, modifiers);
      }
}

static void _record_prototype(
  Compiler c, List binding, Type type, List modifiers) {
  _record_attributes(c, binding, modifiers);
  List contract = _contract(c, type, binding);
  Var stored;
  if (c.semantic_binding_facts().try_get(%(completion $binding), stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    if (state_kind == <definition> || state_kind == <completed>) return;
    if (state_kind != <prototype> || !List.equal(prior_contract, contract)) {
      c.semantic_binding_facts()[%(completion $binding)] = %(conflict);
      return;
    }
  }
  c.semantic_binding_facts()[%(completion $binding)] = %(prototype $contract);
}

/* A source attribute on the prototype belongs to the function; the
   generator writes it on the prototype it derives from the definition. */
static void _record_attributes(Compiler c, List binding, List modifiers) {
  List attributes = NULL;
  foreach (Var item, modifiers)
    if (item is <list> && car(item) is <string>)
      attributes = attributes ? %( @attributes $item ) : %($item);
  if (attributes)
    c.semantic_binding_facts()[%(attributes $binding)] = attributes;
}

static void _record_definition(Compiler c, Type type, List binding) {
  List contract = _contract(c, type, binding);
  Var stored;
  if (c.semantic_binding_facts().try_get(%(completion $binding), stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    if (state_kind == <prototype>) {
      _complete_prototype(c, binding, prior_contract, contract);
      return;
    }
    if (state_kind == <definition> || state_kind == <completed>)
      _report_redefinition(c, "function", binding);
  }
  c.semantic_binding_facts()[%(completion $binding)] = %(definition $contract);
  c.semantic_binding_facts()[%(arms $binding)] = c.arms;
  String spelling = binding_identity_spelling(binding);
  if (spelling && !type.is_static()) c.fn_defs[spelling] = 1;
}

/* A definition completes the prior prototype whose contract it matches. A
   definition without `static` after a `static` prototype keeps the
   prototype's internal linkage in C. */
static void _complete_prototype(
  Compiler c, List binding, List prior_contract, List contract) {
  match (prior_contract)
    case %(function-contract ?a ?b static ?d)
      if (contract.equal(%(function-contract $a $b extern $d))):
        contract = prior_contract;
  if (!List.equal(prior_contract, contract)) {
    String spelling = binding_identity_spelling(binding);
    c.report_error(
      <type>,
      %"definition '$spelling' does not match prior prototype",
      c.token,
      %(
        "prototype: ${prior_contract.repr()}"
        "definition: ${contract.repr()}"
      )
    );
  }
  c.semantic_binding_facts()[%(completion $binding)] = %(completed $contract);
  c.semantic_binding_facts()[%(arms $binding)] = c.arms;
}

static List _contract(Compiler c, Type type, List binding) =>
  _completion_contract(
    type, _fact(c, %(method $binding)), _fact(c, %(self $binding)));

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

static void _record_static_object(Compiler c, Type declared, List bindings) {
  if (!declared.is_static()) return;
  int declared_var = c.sym.is_var_type(declared);
  if (!declared_var && !_initializable_type(c, declared)) return;
  foreach (List binding_init, bindings)
    match (binding_init)
      case %(op = (bind (!set ?binding (binding ? ?)) ?)
             (expr (!set ?initializer_type (*)) ?value)): {
        if (declared_var && !_initializable_type(c, initializer_type))
          continue;
        Map references = {}, Array ordered = [];
        _collect_references(value, references, ordered);
        c.static_init_deps[binding] = ordered.list_free();
      }
}

static int _initializable_type(Compiler c, Type type) =>
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
    case %(expr (!set ?type (*))
           (ident (!set ?binding (binding ? ?)))): {
      if (!type.type().is_function()) {
        if (!references.contains(binding)) ordered.push(binding);
        references[binding] = 1;
      }
      return;
    }
  foreach (Var child, node) _collect_references(child, references, ordered);
}

static void _check_static_inits(Compiler c) {
  Map statics = c.sym.file_statics();
  foreach (Var (key, value), c.static_init_deps) {
    List binding = key, dependencies = value;
    foreach (List reference, dependencies) {
      String name = binding_identity_spelling(reference);
      if (!name || %($name) in statics) continue;
      String target = binding_identity_spelling(binding);
      c.report_error(
        <parse>,
        %"file-static x2c initializer depends on non-static '$name'",
        _init_token(c, binding), target ? %("initializer: $target") : NULL);
    }
  }
}

static Token _init_token(Compiler c, List binding) {
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
static void _append_meta_definitions(Compiler c, Array nodes) {
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
      _record_top_level(c, definition);
      nodes.push(definition);
    }
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

/** Records in `referenced` the identity of every binding `node` names. */
void ast_collect_binding_references(Var node, Map referenced) {
  if (node is not <list>) return;
  List syntax = node;
  // A definition's own binder is a `bind`, so a function does not name itself.
  match (syntax) case %(ident (binding ?identity ?)): {
    referenced[identity] = 1;
    return;
  }
  foreach (Var child, syntax) ast_collect_binding_references(child, referenced);
}
