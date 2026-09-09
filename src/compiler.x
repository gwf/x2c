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

/** Holds scope-owned generated-name state shared by related compilers.

    `Compiler.new` initializes every valid instance; callers borrow it from
    the compiler rather than constructing or freeing it.
*/
typedef struct GenNames {
  Map counters, adapters, int gensym_count;
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

    The structure and its state belong to the current `Scope`. Every new
    compiler is registered for shutdown cleanup, so call `Compiler.free_lisp`
    before its owning `Scope` ends, even when compile-time `Lisp` was not used.
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
  Tokenizer tokenizer;
  List return_type, include_dirs;
  // Canonical dependency path -> content hash for compile-time text reads,
  // or 1 for dependencies whose contents are not embedded in generated C.
  Map deps;
  List aggregate_type, macro_stack, Sym sym;
  SymScope params;
  Map key_ids, macros, kw_aliases;
  // Import paths already applied to this .x file's alias map.
  Map kw_seen;
  // Anchored statements whose transform returned them unchanged. The driver
  // re-walks the unit until it stops changing, so without this every later
  // pass re-derives the whole tree to learn it is already done.
  Map fixed;
  Map protocols, conforms, protocol_helpers;
  // Answers derived from the occurrence and adoption tables. Publishing a
  // protocol or an adoption changes what these would say, so the whole map
  // is dropped there rather than invalidated key by key.
  Map proto_cache;
  // Visible protocol adoptions indexed by base and participant.
  Map adoptions;
  Map macro_holes;
  Map local_macro_captures;
  List lambda_scopes;
  Array match_types;
  // Import path -> declared alias map, or 1 when no aliases need replay.
  Map imports;
  Map init_tokens, static_init_deps, fn_defs;
  Array id_keys, mid_inits;
  String init_fn, fini_fn;
  Array early_decls, proto_inits, early_inits, late_inits, int prelude;
  int runtime_inc, runtime_hdrs, collect_protocols, shallow, source_private;
  int in_pattern, match_is, runtime_literals, inline_header;
  int builtin_defs, in_proto, macro_count, recovery_depth;
  int local_macro_capture_scopes;
  String fn_name, Diagnostics diagnostics, Array braces, import_stack;
  Lisp macro_lisp, String import_src, int borrowed_lisp;
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

protocol Var(Compiler);
#pragma private

List Compiler.lift_func_expression(Compiler compiler, List expression);

#include "utils.x"
#include "parse.x"
#include "protocol.x"
#include "macros.x"
#include <stdlib.h>

/** Merges one translation dependency, preserving an existing content hash. */
void Map.merge_translation_dependency(
  Map dependencies, String path, Var content_hash) {
  if (content_hash is <string>) {
    if (dependencies[path] is not <string>) dependencies[path] = content_hash;
  }
  else dependencies.setdefault(path, 1);
}

/** Records a path dependency not embedded in generated C. */
void Compiler.add_translation_dependency(Compiler compiler, String path) {
  compiler.deps.merge_translation_dependency(path, 1);
}

/** Merges another translation's dependency rows into this compiler. */
void Compiler.merge_translation_dependencies(
  Compiler compiler, Map dependencies) {
  foreach (Var (path, content_hash), dependencies)
    compiler.deps.merge_translation_dependency(path, content_hash);
}

// compiler lifecycle

/* Compilers whose compile-time Lisp is still alive. A compiler that reaches
   process shutdown without Compiler.free_lisp is destroyed from here. */
typedef struct LispOwner {
  Compiler compiler;
  struct LispOwner *next;
} *LispOwner;

static LispOwner compiler_lisp_owners = NULL;
static int compiler_lisp_shutdown_registered = 0;

typedef struct Sym {
  Block scopes, Map globals, statics, binding_facts;
  int base_scopes, next_binding, local_macro_names;
  // Owning compiler, so type resolution can report its own diagnostics.
  Compiler compiler;
} *Sym;

static void _shutdown_lisp(void) {
  while (compiler_lisp_owners) {
    LispOwner owner = compiler_lisp_owners;
    compiler_lisp_owners = owner.next;
    with owner.compiler {
      if (_ && _.macro_lisp && !_.borrowed_lisp) {
        Lisp.destroy(_.macro_lisp);
        _.macro_lisp = NULL;
      }
    }
    free(owner);
  }
}

static void _own_lisp(Compiler compiler) {
  LispOwner owner = malloc(sizeof(struct LispOwner));
  if (!owner) raise %(alloc-fail (owner "Compiler.new"));
  owner.compiler = compiler;
  owner.next = compiler_lisp_owners;
  compiler_lisp_owners = owner;
  if (!compiler_lisp_shutdown_registered) {
    Scope.shutdown_hook(_shutdown_lisp);
    compiler_lisp_shutdown_registered = 1;
  }
}

/** Unregisters a compiler and destroys its owned `Lisp` session, if any.

    A borrowed session is left alive. Owned sessions not freed here are
    destroyed by the process shutdown hook. This is final compiler cleanup:
    it clears the diagnostic store and the compiler must not be reused.
*/
void Compiler.free_lisp(Compiler c) {
  if (!c) return;
  if (c.macro_lisp && !c.borrowed_lisp) {
    Lisp.destroy(c.macro_lisp);
    c.macro_lisp = NULL;
  }
  LispOwner *link = &compiler_lisp_owners;
  while (*link) {
    LispOwner owner = *link;
    if (owner.compiler == c) {
      *link = owner.next;
      free(owner);
      break;
    }
    link = &owner.next;
  }
  c.diagnostics = NULL;
}

static void _emit_user(void *owner, List entry) {
  Compiler compiler = owner;
  if (compiler) compiler.print_diagnostic(entry);
}

/** Routes this compiler's diagnostic store through its own printer.

    Compilers that share a store call this when taking the diagnostic stream
    back from another compiler.
*/
void Compiler.own_diagnostics(Compiler compiler) {
  compiler.diagnostics.set_emitter(_emit_user, compiler);
}

/** Shares a caller's diagnostic stream while preserving its emission policy.
    The caller restores the saved emitter and owner after this child finishes.
*/
void Compiler.borrow_diagnostics(Compiler compiler, Compiler owner) {
  compiler.diagnostics = owner.diagnostics;
  if (compiler.diagnostics.emit == _emit_user) compiler.own_diagnostics();
}

/** Moves collected child reports into the caller's store without re-emitting.
    Shared stores already contain their entries. The child's separate store
    remains configured and empty after its reports have been transferred.
*/
void Compiler.take_diagnostics(Compiler compiler, Compiler child) {
  Diagnostics target = compiler.diagnostics, source = child.diagnostics;
  if (target != source) {
    foreach (Var entry, source.entries) target.entries.push(entry);
    target.count += source.count;
    target.limit_notified |= source.limit_notified;
    source.reset();
  }
}

/** Retains a child's final diagnostics and releases its Lisp registration. */
void Compiler.close_child(Compiler compiler, Compiler child) {
  compiler.take_diagnostics(child);
  child.free_lisp();
}

/* Scope owns the Compiler, Sym, diagnostics, arrays, and maps. Every compiler
   enters the process cleanup list, so Compiler.free_lisp must unregister it
   before that Scope dies. The list is only a fallback for compilers whose
   owning Scope lasts until process shutdown. */
static Compiler _new(Compiler owner) {
  Compiler compiler = Scope.calloc(1, sizeof(struct Compiler));
  with compiler {
    _.id_keys = %[];
    _.key_ids = %{};
    _.deps = %{};
    _.macros = %{};
    _.kw_aliases = %{};
    _.kw_seen = %{};
    _.proto_cache = %{};
    _.imports = %{};
    _.init_tokens = %{};
    _.static_init_deps = %{};
    _.fn_defs = %{};
    if (owner) {
      /* A child compiler owns its tokens, symbols, and diagnostics. Package
         registries and generated-name state belong to the whole translation
         unit, so every child must mutate the owner's exact objects. */
      _.package = owner.package;
      _.package_dirs = owner.package_dirs;
      _.package_roots = owner.package_roots;
      _.package_aliases = owner.package_aliases;
      _.package_members = owner.package_members;
      _.names = owner.names;
      _.source_map = owner.source_map;
      _.recovery_depth = owner.recovery_depth;
      _.sources = owner.sources;
      _.source_facts = owner.source_facts;
      _.source_occurrences = owner.source_occurrences;
      _.source_definitions = owner.source_definitions;
      _.source_declarations = owner.source_declarations;
      _.source_texts = owner.source_texts;
    }
    else {
      _.package_roots = %{};
      _.package_aliases = %{};
      _.package_members = %{};
      _.names = Scope.calloc(1, sizeof(struct GenNames));
      _.names.counters = %{};
      _.names.adapters = %{};
    }
    _.sym = Scope.calloc(1, sizeof(struct Sym));
    with _.sym {
      _.compiler = compiler;
      _.binding_facts = %{};
      _.scopes = Block.new(sizeof(SymScope));
      _.statics = %{};
    }
    _.mid_inits = %[];
    _.early_decls = %[];
    _.proto_inits = %[];
    _.early_inits = %[];
    _.late_inits = %[];
    _.collect_protocols = 1;
    _own_lisp(_);
    _.diagnostics = Diagnostics.new(_emit_user, _, 1);
    if (owner && owner.diagnostics.emit != _emit_user)
      _.diagnostics.set_emitter(
        owner.diagnostics.emit, owner.diagnostics.owner);
    _.braces = %[];
    _.import_stack = %[];
    _.origins = %[];
    _.root_dir = x2c_get_root();
    return _;
  }
}

/** Creates a compiler with independent package and generated-name state. */
Compiler Compiler.new(void) => _new(NULL);

/** Creates a compiler sharing its owner's package and generated-name state. */
Compiler Compiler.new_shared(Compiler owner) {
  /* Shallow collection compilers must declare into the same package space,
     and share the owner's package maps so an import seen in one segment is
     registered and collected exactly once for the whole unit. */
  return _new(owner);
}

/** Reads a source through the request view and retains exact response bytes. */
int Compiler.read_source(
  Compiler compiler, String path, String volatile *text) {
  if (!compiler.sources.read(path, text)) return 0;
  if (compiler.source_facts)
    compiler.source_texts[SourceView.path(path)] = *text;
  return 1;
}

/** Carries declaration metadata with one actual symbol contribution. */
void Compiler.copy_source_declaration(
  Compiler compiler, Map target, Map source, List key) {
  if (!compiler.source_facts) return;
  Var declaration;
  List target_key = %($target $key);
  if (compiler.source_declarations.try_get(%($source $key), &declaration))
    compiler.source_declarations[target_key] = declaration;
  else compiler.source_declarations.del(target_key);
}

/** Carries declaration metadata beside a completed symbol-map merge. */
void Compiler.merge_source_declarations(
  Compiler compiler, Map target, Map source) {
  if (!compiler.source_facts) return;
  foreach (Var key, source.keys())
    if (key is <list>) compiler.copy_source_declaration(target, source, key);
}

static List _source_range(Compiler compiler, Token first, Token after) {
  if (!first || !after || first >= after || compiler.macro_holes) return NULL;
  Token last = after - 1;
  while (last > first &&
         (last.type == <space> || last.type == <comment> ||
          last.type == <preproc>)) last--;
  String path = SourceView.path(compiler.filename);
  if (!compiler.source_texts.contains(path))
    compiler.source_texts[path] = compiler.text;
  return %($path ${first.pos} ${last.pos + last.len});
}

/** Records a physical declaration using the binding's actual scope and key. */
void Compiler.record_source_declaration(
  Compiler compiler, List binding, Token first, Token after) {
  if (!compiler.source_facts || compiler.macro_holes) return;
  Var value;
  if (!compiler.semantic_binding_facts().try_get(
      %(src-key $binding), &value)) return;
  List source_key = value, range = _source_range(compiler, first, after);
  if (!range) return;
  Map symbols = source_key.car();
  List key = source_key.cadr();
  Type type = symbols[key];
  List declaration = %(@range $type);
  compiler.source_declarations[source_key] = declaration;
  if (compiler.source_primary && !compiler.shallow) {
    compiler.source_definitions[binding] = declaration;
    compiler.source_occurrences.push(%(@range $binding $type));
  }
}

/** Records a resolved reference without inventing spans for constructed ASTs. */
void Compiler.record_source_reference(
  Compiler compiler, List binding, Type type, Token first, Token after) {
  if (!compiler.source_facts || !compiler.source_primary || compiler.shallow ||
      compiler.macro_holes ||
      !binding_identity_try_parts(binding, NULL, NULL)) return;
  List range = _source_range(compiler, first, after);
  if (range) compiler.source_occurrences.push(%(@range $binding $type));
}

/** Returns the current borrowed semantic-facts map indexed by binding.

    A semantic transaction may replace this map, so reacquire it afterwards.
*/
Map Compiler.semantic_binding_facts(Compiler compiler) =>
  compiler.sym.binding_facts;

/** Returns the active macro definition's borrowed local map, or `NULL`. */
Map Compiler.macro_definition_locals(Compiler compiler) {
  Var stored = compiler.macro_holes[%(locals)];
  return stored is <map> ? stored.map() : NULL;
}

/** Allocates the next compiler-private C spelling for `stem`.

    Related compilers increment the same per-stem counter.
*/
String Compiler.fresh_name(Compiler compiler, String stem) {
  Var stored;
  int count = compiler.names.counters.try_get(stem, &stored)
            ? stored.int() : 0;
  String name = %"_x2c_${stem}_${count++}";
  compiler.names.counters[stem] = count;
  return name;
}

/** Returns a binding's selected emitted spelling.

    A binding without an explicit emission rename uses its identity spelling.
*/
String Compiler.emitted_binding_name(Compiler compiler, List binding) {
  Var renamed;
  if (compiler.semantic_binding_facts().try_get(
    %(emitted $binding), &renamed))
    return renamed.str();
  return binding_identity_spelling(binding);
}

/** Scans source and positions the compiler at its first non-trivia token.

    The compiler borrows `text` for diagnostics and macro source capture until
    translation finishes.
*/
void Compiler.tokenize(Compiler c, char *text) {
  c.text = text;
  c.tokenizer = Tokenizer.new(c.text);
  c.tokenizer.scan();
  c.token = _skip_forward(c.tokenizer.tokens);
  c.braces.clear();
}

// token navigation

static Token _skip_backward(Token token, Token origin) {
  while (token > origin) {
    switch (token.type) {
      case <space>: case <comment>: case <preproc>: token--; break;
      default: return token;
    }
  }
  return origin;
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

/** Returns the first non-trivia token at or after `token`. */
Token Compiler.skip_trivia_from(Compiler compiler, Token token) =>
  _skip_forward(token);

/** Returns the non-trivia token type `steps` from parser position.

    Zero reads the current token; positive and negative steps count forward
    and backward through non-trivia tokens. The parser cursor is unchanged.
*/
Symbol Compiler.peek(Compiler compiler, int steps) {
  Token token = compiler.token;
  while (steps > 0) {
    token = _skip_forward(token + 1);
    steps--;
  }
  while (steps < 0) {
    token = _skip_backward(token - 1, compiler.tokenizer.tokens);
    steps++;
  }
  return token.type;
}

/** Requires and consumes the current token type.

    A mismatch reports a parse diagnostic. An active recovery boundary raises
    `<malformed>`; without one, diagnostic reporting exits.
*/
Symbol Compiler.expect(Compiler c, Symbol type) {
  if (c.token.type != type)
    c.report_error(<parse>, %"expected '$type'", c.token, NULL);
  c.next();
  return type;
}

// Unmatched-brace diagnostics use this source-order stack.
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

/** Consumes the current token and advances past following trivia.

    This updates the unmatched-brace stack. An unmatched `}` reports a parse
    diagnostic, which raises `<malformed>` under recovery and otherwise exits.
*/
void Compiler.next(Compiler compiler) {
  Token consumed = compiler.token;
  if (consumed.type == <eof>) return;
  compiler.token = _skip_forward(consumed + 1);
  _update_brace_stack(compiler, consumed);
}

/** Consumes `type` when current and reports whether it matched. */
inline int Compiler.test(Compiler compiler, Symbol type) {
  if (compiler.token.type != type) return 0;
  compiler.next();
  return 1;
}

static void _check_unmatched_braces(Compiler c) {
  if (!c.braces.len()) return;
  c.report_error(
    <parse>, "missing '}'", c.braces[-1],
    %( "'{' opened here" ));
}

static void _shallow_block(Compiler c) {
  Symbol peek;
  c.next();
  while ((peek = c.peek(0)) != <"}">) {
    if (peek == <eof>)
      c.report_error(<parse>, "unexpected end of file", c.token, NULL);
    if (peek == <"{"> || peek == <"%{"> ||
        peek == <"${"> || peek == <"@{">)
      _shallow_block(c);
    else c.next();
  }
  c.expect(<"}">);
}

/** Records a token's location and returns its one-based occurrence.

    A null token returns zero. Callers pass the token that opened a construct,
    so an `(at N node)` wrapper retains its start for transform diagnostics
    after `compiler.token` has reached end of file.
*/
int Compiler.record_origin(Compiler c, Token token) {
  if (!token) return 0;
  String file = c.filename ? c.filename : %"<stdin>";
  if (!c.source_map) file = c.display_path(file);
  c.origins.push(
    %(source $file ${token.line} ${token.col} ${token.len} ${token.pos}));
  return c.origins.len();
}

/** Wraps a parsed node in the source location of its opening token.

    A null node remains null. Macro construction uses its active `m-origin`
    marker; otherwise a node without a token remains unwrapped.
*/
List Compiler.anchor_origin(Compiler compiler, List node, Token token) {
  if (!node) return node;
  if (compiler.macro_holes) return %(at m-origin $node);
  int occurrence = compiler.record_origin(token);
  if (!occurrence) return node;
  return %(at $occurrence $node);
}

static int _shallow_parse_compile_time_definition(
  Compiler c, int keyword) {
  int old_depth = c.recovery_depth, failed = 0;
  Diagnostics diag = c.diagnostics;
  DiagnosticEmitter emitter = diag.emit;
  void *owner = diag.owner;
  int entries = diag.entries.len(), count = diag.count;
  int limited = diag.limit_notified;
  diag.set_emitter(NULL, NULL);
  c.recovery_depth = old_depth + 1;
  try {
    if (keyword) c.parse_keyword_definition();
    else c.parse_macro_definition();
  }
  catch %(malformed *): failed = 1;
  c.recovery_depth = old_depth;
  diag.set_emitter(emitter, owner);
  diag.entries.resize(entries);
  diag.count = count;
  diag.limit_notified = limited;
  if (failed) while (c.peek(0) != <eof>) c.next();
  return !failed;
}

static List _shallow_parse_declaration(Compiler compiler) {
  List declaration = compiler.parse_declaration_row();
  compiler.record_declaration_visibility(declaration);
  return declaration;
}

// Remember the spelling of one function body found while collecting `.x`.
static void _shallow_record_function_definition(
  Compiler compiler, Type type, List binding) {
  if (!type.is_function() || type.is_static()) return;
  compiler.fn_defs[binding_identity_spelling(binding)] = 1;
}

/** Reports whether the current two tokens are `=>`. */
int Compiler._at_function_arrow(Compiler compiler) =>
  compiler.peek(0) == <=> && compiler.peek(1) == <">">;

/** Skips a balanced shallow expression without consuming its terminator.
    A top-level comma also terminates the expression when `stop_at_comma` is
    nonzero.
*/
void Compiler._skip_shallow_expression(
  Compiler compiler, int stop_at_comma) {
  int parens = 0, brackets = 0, braces = 0;
  while (compiler.peek(0) != <eof>) {
    Symbol token = compiler.peek(0);
    if (token == <"$(">) {
      compiler.skip_macro_lisp();
      continue;
    }
    if (!parens && !brackets && !braces &&
        (token == <;> || (stop_at_comma && token == <,>)))
      return;
    if (token == <(> || token == <"?(">) parens++;
    else if (token == <)> && parens) parens--;
    else if (token == <[> || token == <"%[">)
      brackets++;
    else if (token == <]> && brackets) brackets--;
    else if (token == <"{"> || token == <"%{"> ||
             token == <"${"> || token == <"@{">) braces++;
    else if (token == <"}"> && braces) braces--;
    compiler.next();
  }
}

static void _shallow_finish_declaration(Compiler c) {
  List declaration = _shallow_parse_declaration(c);
  if (c.peek(0) == <"{"> || c.peek(0) == <"%{"> ||
      c._at_function_arrow()) {
    match (declaration)
      case %(declare ?type (bindings (bind ?binding ?))):
        _shallow_record_function_definition(
          c, type, binding);
    if (c._at_function_arrow()) {
      c.next();
      c.next();
      c._skip_shallow_expression(0);
      c.expect(<;>);
    }
    else _shallow_block(c);
  }
  else if (c.peek(0) == <;>) c.next();
  else c.next();
}

/* Expand an imported file-scope unit macro so later invocations can use its
   private helpers and other units can see its public declarations. */
static void _shallow_parse_unit_macro(Compiler compiler) {
  with compiler.names {
    Map saved_counters = _.counters;
    int saved_gensym = _.gensym_count;
    _.counters = _.counters.copy();
    with compiler {
      SymTxn transaction = _.begin_semantic_transaction();
      (void) _.parse_top_level();
      transaction.commit();
    }
    /* The full parse expands this unit again. Keep the declarations needed
       by later shallow invocations, but do not count its generated names
       twice. */
    _.counters = saved_counters;
    _.gensym_count = saved_gensym;
  }
}

static void _shallow_parse_loop(Compiler c) {
  c.rebuild_protocols(NULL);
  c.conforms = %{};
  c.shallow = 1;
  c.braces.clear();
  while (c.peek(0) != <eof>) {
    c.update_source_visibility(c.leading_preproc());
    Token start = c.token;
    if (c.test_static_assert()) {
      c.parse_static_assert();
      _debug_tokens(c, start, c.token);
      continue;
    }
    if (c.peek(0) == <"$(">) {
      c.parse_macro_lisp_shallow();
      _debug_tokens(c, start, c.token);
      continue;
    }
    // Collection performs the import: the package's names must reach the
    // globs this segment contributes before any later segment names it.
    if (c.peek(0) == <import>) {
      c.parse_import_declaration();
      _debug_tokens(c, start, c.token);
      continue;
    }
    if (c.peek(0) == <protocol> ||
        (c.peek(0) == <static> && c.peek(1) == <protocol>)) {
      c.parse_protocol_declaration();
      _debug_tokens(c, start, c.token);
      continue;
    }
    if (c.keyword_form_is_definition()) {
      _shallow_parse_compile_time_definition(c, 1);
      _debug_tokens(c, start, c.token);
      continue;
    }
    int macro_definition = c.macro_form_is_definition();
    int keyword_alias = c.keyword_alias_starts_target_at(AST_UNIT);
    if (macro_definition || c.peek(0) == <$> || keyword_alias) {
      if (macro_definition)
        _shallow_parse_compile_time_definition(c, 0);
      else if (c.collect_protocols &&
               (keyword_alias
                  ? c.keyword_alias_needs_shallow_expansion()
                  : c.macro_invocation_needs_shallow_expansion()))
        _shallow_parse_unit_macro(c);
      else {
        if (keyword_alias) c.skip_keyword_alias();
        else c.skip_macro_invocation();
        if (!c.test(<;>)) {
          while (c.peek(0) == <$> ||
                 c.keyword_alias_starts_target_at(AST_UNIT)) {
            if (c.peek(0) == <$>) c.skip_macro_invocation();
            else c.skip_keyword_alias();
            if (c.test(<;>)) break;
          }
          if (c.peek(-1) != <;>) _shallow_finish_declaration(c);
        }
      }
      _debug_tokens(c, start, c.token);
      continue;
    }
    _shallow_finish_declaration(c);
    _debug_tokens(c, start, c.token);
  }
  _check_unmatched_braces(c);
  c.shallow = 0;
}

/** Collects file-scope declarations into `globals` without parsing bodies. */
void Compiler.shallow_parse(Compiler c, Map globals) {
  c.macros = %{};
  c.kw_aliases = %{};
  c.kw_seen = %{};
  c.imports = %{};
  c.import_stack.clear();
  c.sym.reset(globals);
  c.install_builtin_macros();
  _shallow_parse_loop(c);
}

/** Collects declarations with reads over `base` then `overlay`.

    Writes go to `overlay`, which captures exactly what this translation
    contributes above `base`.
*/
void Compiler.shallow_parse_overlay(Compiler c, Map base, Map overlay) {
  int initialize_macros =
    (void *) c.macros == NULL || !c.macros.len();
  if (initialize_macros) {
    c.macros = %{};
    if ((void *) c.kw_aliases == NULL) c.kw_aliases = %{};
    if ((void *) c.kw_seen == NULL) c.kw_seen = %{};
    c.imports = %{};
    c.import_stack.clear();
  }
  c.sym._reset_overlay(base, overlay);
  if (initialize_macros) c.install_builtin_macros();
  _shallow_parse_loop(c);
}

/** Returns source-ordered preprocessor nodes in the preceding trivia.

    Spaces and comments remain trivia rather than becoming AST nodes.
*/
List Compiler.leading_preproc(Compiler compiler) {
  List noncode = NULL;
  Token base = compiler.tokenizer.tokens, token = compiler.token;
  if (token == base) return NULL;
  while (--token >= base) {
    switch (token.type) {
      case <space>: case <comment>: break;
      case <preproc>:
        noncode = cons(%( preproc ${token.text} ), noncode); break;
      default: return noncode;
    }
  }
  return noncode;
}

/** Applies public and private pragma directives to source visibility state.

    A negative visibility state disables pragma tracking for this token
    stream.
*/
void Compiler.update_source_visibility(Compiler c, List directives) {
  if (c.source_private < 0) return;
  foreach (List directive, directives) {
    String content = directive.cadr();
    if (content.contains("pragma private")) c.source_private = 1;
    else if (content.contains("pragma public")) c.source_private = 0;
  }
}

// Prepend source-ordered directives to an AST accumulated in reverse order.
static List _prepend_preproc(Compiler compiler, List ast) {
  List directives = compiler.leading_preproc();
  compiler.update_source_visibility(directives);
  foreach (Var directive, directives) ast = cons(directive, ast);
  return ast;
}

static void _sync_top_level(Compiler c) {
  int depth = 0;
  while (c.peek(0) != <eof>) {
    Symbol sym = c.peek(0);
    if (depth == 0 && (sym == <;> || sym == <"}">)) {
      c.next();
      break;
    }
    if (sym == <"{"> || sym == <"%{"> ||
        sym == <"${"> || sym == <"@{">) {
      depth += 1;
      c.next();
      continue;
    }
    if (sym == <"}"> && depth > 0) {
      depth -= 1;
      c.next();
      if (depth == 0) break;
      continue;
    }
    c.next();
  }
}

/** Parses and types the positioned source against `globs`.

    The result is a source-ordered top-level AST. This resets per-parse
    origins, macro state, protocol resolution, and recoverable diagnostics.
*/
List Compiler.full_parse(Compiler c, Map globs) {
  List ast = NULL;
  c.origins.clear();
  c.fixed = %{};
  c.init_tokens = %{};
  c.static_init_deps = %{};
  c.origin = 0;
  c.braces.clear();
  c.sym.reset(globs);
  c.rebuild_protocols(globs);
  c.macros = %{};
  c.kw_aliases = %{};
  c.kw_seen = %{};
  c.install_builtin_macros();
  c.imports = %{};
  c.import_stack.clear();
  c.macro_count = 0;
  c.macro_stack = NULL;
  c.source_private = 0;
  c.diagnostics.reset();
  c.resolve_protocols();
  int old_depth = c.recovery_depth;
  c.recovery_depth = old_depth + 1;
  {
    defer c.recovery_depth = old_depth;
    ast = _prepend_preproc(c, ast);
    while (c.peek(0) != <eof>) {
      try {
        Token start = c.token;
        Ast node = c.parse_top_level();
        if (node && node.car() == <seq>) {
          foreach (List item, node.cdr()) {
            _record_top_level_function_state(c, item);
            ast = cons(item, ast);
          }
        }
        else if (node) {
          _record_top_level_function_state(c, node);
          ast = cons(node, ast);
        }
        ast = _prepend_preproc(c, ast);
        _debug_tokens(c, start, c.token);
      }
      catch %(malformed (category ?category) *): {
        (void) category;
        if (c.diagnostics.reached_limit()) break;
        _sync_top_level(c);
        ast = _prepend_preproc(c, ast);
        if (c.peek(0) == <eof>) break;
        continue;
      }
    }
  }
  ast = ast.reverse();
  _check_unmatched_braces(c);
  if (!c.error_count()) _validate_static_object_initializers(c);
  return ast;
}

static void _debug_tokens(Compiler compiler, Token start, Token end) {
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

// cache & init management

static List _cache_alias(List key) {
  match (key) {
    case %(cache ?):                          return key;
    case %(expr ? (cache ?id)):               return %(cache $id);
    case %(var (expr ("Var") (cache ?id))):   return %(cache $id);
    case %(expr ("List") (cache ?id)):        return %(cache $id);
  }
  return NULL;
}

/** Interns a constant key and returns its stable `(cache id)` reference. */
List Compiler.cache(Compiler c, List key) {
  List alias = _cache_alias(key);
  if (alias) return alias;
  int nextid = c.id_keys.len(), id = c.key_ids.setdefault(key, nextid);
  if (id == nextid) c.id_keys.push(key);
  return %(cache $id);
}

/** Caches a cons cell when both parts have immutable cache forms.

    Returns `NULL` when runtime literals are required or either part cannot
    be represented by the immutable cache graph.
*/
List Compiler.cache_cons_cell(Compiler compiler, List head, List tail) {
  if (compiler.runtime_literals) return NULL;
  List head_cache = NULL, tail_cache = NULL;
  if (head.match(%(expr ("Var") (cache *)))) head_cache = head.caddr();
  else if (head.match(%(cache *))) head_cache = head;
  if (!head_cache) return NULL;
  if (tail.match(%(expr ("List") (cache *)))) tail_cache = tail.caddr();
  else if (tail.match(%(nil))) tail_cache = tail;
  if (!tail_cache) return NULL;
  List cached = compiler.cache(%(cons $head_cache $tail_cache));
  return %(expr ("List") $cached);
}

static List _cache_literal_list(Compiler compiler, List values);

static List _cache_literal_var(Compiler compiler, Var value) {
  if (value is <list>) {
    List cached = _cache_literal_list(compiler, value);
    return compiler.cache(%( var (expr ("List") (expr ("List") $cached)) ));
  }
  if (value is <string>) {
    List literal = %(expr ("String") (literal ("String") $value));
    List cached = compiler.cache(%(string $literal));
    return compiler.cache(%(var (expr ("String") $cached)));
  }
  String spelling = value.symbol();
  List literal = %(
    expr ("Symbol") (literal ("Symbol") $spelling $value)
  );
  return compiler.cache(%(var $literal));
}

static List _cache_literal_list(Compiler compiler, List values) {
  Array heads = %[];
  defer heads.free();
  foreach (Var value, values)
    heads.push(_cache_literal_var(compiler, value));
  List result = %(nil);
  for (int i = (int) heads.len() - 1; i >= 0; i--) {
    List head = heads[i];
    result = compiler.cache(%(cons $head $result));
  }
  return result;
}

/** Returns a runtime `List` expression for cached compiler-owned syntax.

    `values` may contain nested `List`s, `String`s, and `Symbol`s.
*/
List Compiler.cache_literal_list(Compiler compiler, List values) {
  List cached = _cache_literal_list(compiler, values);
  return %(expr ("List") (expr ("List") $cached));
}

/* Recover the compile-time value graph behind a Match pattern.  Dynamic
   expressions are represented by a private marker so binder analysis can
   distinguish a computed operator head from ordinary literal data. */
static String _match_pattern_converter_name(Var node) {
  if (node is <string>) return node.str();
  if (node is not <list>) return NULL;
  List matched = node.list().match(%(expr ? (ident ?binding)));
  if (!matched) return NULL;
  List binding = matched.assoc(<?binding>);
  return binding_identity_spelling(binding);
}

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
  String converter = head == <call>
                   ? _match_pattern_converter_name(second) : NULL;
  if (converter == %"List_var" || converter == %"Symbol_var") {
    List args = third;
    Var (args_tag, argument) = args;
    if (args && args_tag == <args> && args.cdr() && !args.cddr())
      return c.match_pattern_value(argument);
  }
  if (head == <literal>) return ast.last();
  if (head == <nil>) return %();
  if (head == <cons>) {
    Var value = c.match_pattern_value(second);
    Var tail = c.match_pattern_value(third);
    if (tail is not <list>) return <x2c-dyn>;
    return cons(value, tail);
  }
  return <x2c-dyn>;
}

static int _match_pattern_value_is_static(Var value) {
  if (value == <x2c-dyn>) return 0;
  if (value is not <list>) return 1;
  foreach (Var part, value.list())
    if (!_match_pattern_value_is_static(part)) return 0;
  return 1;
}

/** Reports whether a typed `Match` pattern has a fully static value graph. */
int Compiler.match_pattern_is_static(Compiler compiler, List pattern) =>
  _match_pattern_value_is_static(
    compiler.match_pattern_value(pattern));

/** Returns a typed `Match` pattern's fixed literal head symbol, or zero.

    A binder, guard, non-list value, or computed head has no fixed symbol.
    Other pattern elements may remain dynamic because a literal head alone
    constrains the first input element.
*/
Symbol Compiler.match_pattern_head_symbol(Compiler compiler, List pattern) {
  Var value = compiler.match_pattern_value(pattern);
  if (value is not <list>) return 0;
  Var head = car(value);
  if (head is not <symbol> || head == <x2c-dyn> ||
      head.is_binder() || head.is_match_op())
    return 0;
  return head;
}

/** Returns the head of a flat Symbol-and-captures pattern, or zero.
    The analyzed binder list contains each definite name once, in order.
*/
Symbol Compiler.match_pattern_flat_head(
  Compiler compiler, List pattern, List binders) {
  Symbol head = compiler.match_pattern_head_symbol(pattern);
  if (!head) return 0;
  List value = compiler.match_pattern_value(pattern);
  if (!value.cdr().equal(binders)) return 0;
  foreach (Var binder, binders)
    if (!binder.is_atom_binder() || binder == <?>) return 0;
  return head;
}

/** Returns definite binders from a typed `Match` pattern AST.

    When `possible` is non-null, stores every binder appearing on any path.
*/
List Compiler.match_pattern_binders(
  Compiler compiler, List pattern, List *possible) {
  Var value = compiler.match_pattern_value(pattern);
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(value);
  List definite = layout.definite_list();
  if (possible) *possible = layout.possible_list();
  layout.free();
  return definite;
}

/** Defines a typed `Match` pattern's definite binders in the current scope. */
void Compiler.define_match_binders(Compiler compiler, List pattern) {
  foreach (Var binder, compiler.match_pattern_binders(pattern, NULL)) {
    String name = binder.str()[1:];
    List type = binder.is_list_binder() ? %("List") : %("Var");
    compiler.sym.define(%($name), type);
  }
}

/** Appends a generated declaration to the early-declaration queue. */
void Compiler.add_early(Compiler compiler, List decl) {
  compiler.early_decls.push(decl);
}

/** Appends a statement to protocol initialization order. */
void Compiler.add_protocol_init(Compiler compiler, List stmt) {
  compiler.proto_inits.push(stmt);
}

/** Appends a statement to early file initialization order. */
void Compiler.add_early_init(Compiler compiler, List stmt) {
  compiler.early_inits.push(stmt);
}

/** Appends a statement to middle file initialization order. */
void Compiler.add_mid_init(Compiler compiler, List stmt) {
  compiler.mid_inits.push(stmt);
}

/** Appends a statement to late file initialization order. */
void Compiler.add_late_init(Compiler compiler, List stmt) {
  compiler.late_inits.push(stmt);
}

// symbol table

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

static SymScope *_semantic_scope(Sym sym, int index) {
  int count = sym.scopes.len();
  if (index < 0) index += count;
  if (index < 0 || index >= count) return NULL;
  SymScope *scopes = sym.scopes.bytes;
  return scopes + index;
}

typedef struct SymTxn {
  Compiler compiler;
  int scope_index, next_binding, active, String initializer_name;
  String shutdown_name, Map counters;
  int gensym_count, local_macro_names;
  SymScope scope;
  Map statics, binding_facts;
  Map source_definitions;
  int source_occurrences;
} *SymTxn;

/** Begins a reversible transaction over the current semantic scope.

    The transaction stages the current scope maps, file-static and binding
    facts, binding and generated-name counters, and initializer names. It
    does not snapshot parser position or other compiler state.
*/
SymTxn Compiler.begin_semantic_transaction(Compiler c) {
  SymTxn transaction =
    Scope.calloc(1, sizeof(struct SymTxn));
  transaction.compiler = c;
  transaction.scope_index = c.sym.scopes.len() - 1;
  SymScope *scope =
    _semantic_scope(c.sym, transaction.scope_index);
  transaction.scope = *scope;
  transaction.counters = c.names.counters;
  transaction.gensym_count = c.names.gensym_count;
  transaction.statics = c.sym.statics;
  transaction.binding_facts = c.semantic_binding_facts();
  transaction.next_binding = c.sym.next_binding;
  transaction.local_macro_names = c.sym.local_macro_names;
  transaction.initializer_name = c.init_fn;
  transaction.shutdown_name = c.fini_fn;
  if (c.source_facts && c.source_primary) {
    transaction.source_definitions = c.source_definitions.copy();
    transaction.source_occurrences = c.source_occurrences.len();
  }

  /* Macro binding is incremental. Copy only the maps that construction
     mutates so failure can discard its rows while reads still reach the
     unchanged outer scopes. */
  scope.symbols = transaction.scope.symbols.copy();
  c.merge_source_declarations(scope.symbols, transaction.scope.symbols);
  scope.bindings = transaction.scope.bindings.copy();
  scope.enumerators = transaction.scope.enumerators.copy();
  scope.macros = (void *) transaction.scope.macros != NULL
               ? transaction.scope.macros.copy() : NULL;
  c.sym.statics = c.sym.statics.copy();
  c.sym.binding_facts =
    c.semantic_binding_facts().copy();
  c.names.counters = c.names.counters.copy();
  transaction.active = 1;
  return transaction;
}

/** Publishes an active semantic transaction and makes rollback a no-op. */
void SymTxn.commit(SymTxn s) {
  if (!s || !s.active) return;
  Compiler compiler = s.compiler;
  SymScope *scope =
    _semantic_scope(compiler.sym, s.scope_index);
  SymScope staged = *scope;
  /* Restore the original map identities before merging staged rows. Code
     holding a borrowed scope map must observe a committed expansion. */
  *scope = s.scope;
  Map.merge(scope.symbols, staged.symbols);
  compiler.merge_source_declarations(scope.symbols, staged.symbols);
  Map.merge(scope.bindings, staged.bindings);
  Map.merge(scope.enumerators, staged.enumerators);
  if ((void *) staged.macros != NULL) {
    if ((void *) scope.macros == NULL) scope.macros = %{};
    Map.merge(scope.macros, staged.macros);
  }
  s.active = 0;
}

/** Returns whether the transaction's active scope changed its macro map. */
int SymTxn.local_macros_changed(SymTxn transaction) {
  SymScope *scope = _semantic_scope(
    transaction.compiler.sym, transaction.scope_index);
  Map before = transaction.scope.macros, after = scope.macros;
  if ((void *) before == NULL || (void *) after == NULL)
    return (void *) before != (void *) after;
  return !Map.equal(before, after);
}

/** Restores every semantic value captured by an active transaction. */
void SymTxn.rollback(SymTxn transaction) {
  if (!transaction || !transaction.active) return;
  Compiler compiler = transaction.compiler;
  with compiler {
    SymScope *scope =
      _semantic_scope(_.sym, transaction.scope_index);
    *scope = transaction.scope;
    _.sym.statics = transaction.statics;
    _.sym.binding_facts = transaction.binding_facts;
    _.sym.next_binding = transaction.next_binding;
    _.sym.local_macro_names = transaction.local_macro_names;
    _.names.counters = transaction.counters;
    _.names.gensym_count = transaction.gensym_count;
    _.init_fn = transaction.initializer_name;
    _.fini_fn = transaction.shutdown_name;
    if (_.source_facts && _.source_primary) {
      _.source_occurrences.resize(transaction.source_occurrences);
      foreach (Var key, _.source_definitions.keys().list())
        _.source_definitions.del(key);
      Map.merge(_.source_definitions, transaction.source_definitions);
    }
    transaction.active = 0;
  }
}

static void _semantic_reset(Sym sym, Map base, Map globals, int overlay) {
  sym.scopes.clear();
  sym.globals = (void *) globals != NULL ? globals : %{};
  sym.statics = %{};
  sym.base_scopes = overlay ? 2 : 1;
  sym.next_binding = 0;
  sym.local_macro_names = 0;
  sym.binding_facts = %{};
  if (overlay) {
    struct SymScope base_scope = {
      .symbols = (void *) base != NULL ? base : %{},
      .bindings = %{}, .enumerators = %{}
    };
    sym.scopes.push(&base_scope);
  }
  struct SymScope scope = {
    .symbols = sym.globals,
    .bindings = %{},
    .enumerators = %{}
  };
  sym.scopes.push(&scope);
}

/** Resets symbol state to one base scope backed by `globals`.

    Later definitions mutate that caller-supplied map.
*/
void Sym.reset(Sym sym, Map globals) {
  _semantic_reset(sym, NULL, globals, 0);
}

static void Sym._reset_overlay(Sym sym, Map base, Map overlay) {
  _semantic_reset(sym, base, overlay, 1);
}

/** Returns the mutable global symbol map supplied to the latest reset. */
Map Sym.global_symbols(Sym sym) => sym.globals;

/** Copies all base-scope symbols into a fresh map in source order.

    Package collection uses this so it resolves against the prelude and the
    importing unit's already-visible includes without mutating either.
*/
Map Sym.base_symbols(Sym sym) {
  Map seed = %{};
  for (int i = 0; i < sym.base_scopes; i++)
    Map.merge(seed, _semantic_scope(sym, i).symbols);
  return seed;
}

/** Returns the current borrowed set of file-static declaration keys.

    A semantic transaction may replace this map, so reacquire it afterwards.
*/
Map Sym.file_statics(Sym sym) => sym.statics;

/** Marks a declaration key as file-static. */
void Sym.mark_static(Sym sym, List key) {
  sym.statics[key] = 1;
}

/** Returns the current scope's mutable symbol map, or `NULL`. */
Map Sym.current_symbols(Sym sym) {
  SymScope *scope = _semantic_scope(sym, -1);
  return scope ? scope.symbols : NULL;
}

/** Returns `key`'s binding in the current scope, or `NULL`. */
List Sym.current_binding(Sym sym, List key) {
  SymScope *scope = _semantic_scope(sym, -1);
  Var binding;
  return scope && scope.bindings.try_get(key, &binding)
       ? binding.list() : NULL;
}

/** Returns the current scope's enum owner for `key`, or zero. */
Symbol Sym.enumerator_owner(Sym sym, List key) {
  SymScope *scope = _semantic_scope(sym, -1);
  Var owner;
  return scope && scope.enumerators.try_get(key, &owner)
       ? owner.symbol() : 0;
}

/** Associates an enumerator key with its owner in the active scope. */
void Sym.declare_enumerator(Sym sym, List key, Symbol owner) {
  SymScope *scope = _semantic_scope(sym, -1);
  if (scope) scope.enumerators[key] = owner;
}

/** Defines or replaces a macro in the active lexical scope.

    Captured bindings are recorded for later shadow handling. Replacing a
    name already defined in this scope does not increase the local macro
    count.
*/
void Sym.define_macro(Sym sym, Atom name, List definition) {
  SymScope *scope = _semantic_scope(sym, -1);
  if ((void *) scope.macros == NULL) scope.macros = %{};
  if (!scope.macros.contains(name)) sym.local_macro_names++;
  scope.macros[name] = definition;
  Var captures = definition.assoc(<captures>);
  if (captures is <list>) foreach (Var capture, captures.list())
    if (capture is <list>)
      sym.binding_facts[%(local-macro-capture ${capture.list()})] = 1;
}

/** Returns whether any lexical scope contains a local macro definition. */
int Sym.has_local_macros(Sym sym) => sym.local_macro_names != 0;

/** Returns the number of semantic scopes, including base scopes. */
int Sym.scope_count(Sym sym) => sym.scopes.len();

/** Returns the innermost visible local macro named `name`, or `NULL`. */
List Sym.lookup_macro(Sym sym, Atom name) {
  Var definition;
  for (int i = (int) sym.scopes.len() - 1;
       i >= sym.base_scopes; i--) {
    SymScope *scope = _semantic_scope(sym, i);
    if ((void *) scope.macros != NULL &&
        scope.macros.try_get(name, &definition))
      return definition;
  }
  return NULL;
}

static int _retained_aggregate_member(List key) =>
  !!key.match(%((!or struct union)
    (!or (binding ? ?) (gensym ?)) ? *));

/** Sets a semantic type for `key` in the required active scope. */
void Sym.set(Sym sym, List key, List type) {
  SymScope *current = _semantic_scope(sym, -1);
  Map scope = current.symbols;
  if (log_should_log(<debug>, <symtab>))
    log_debug(<symtab>, %( (func "Sym.set") (key $key) (val $type) ));
  scope[key] = type;
  if (_retained_aggregate_member(key))
    sym.binding_facts[%(aggfact $key)] = type;
}

static List _semantic_new_binding(Sym sym, List key) {
  sym.next_binding++;
  Var name = key.last();
  List binding = binding_identity_new(sym.next_binding, name.str());
  sym.binding_facts[%(known ${sym.next_binding})] =
    name;
  return binding;
}

static List _semantic_scope_binding(Sym sym, SymScope *scope, List key) {
  Var found;
  List binding;
  if (scope.bindings.try_get(key, &found)) binding = found;
  else {
    binding = _semantic_new_binding(sym, key);
    scope.bindings[key] = binding;
  }
  (Var binding_tag, int identity, String spelling) = binding;
  (void) binding_tag;
  if (!sym.binding_facts.contains(%(known $identity)))
    sym.binding_facts[%(known $identity)] = spelling;
  List self_key = %(self $binding);
  if (!sym.binding_facts.contains(self_key)) {
    Var relative;
    if (scope.symbols.try_get(%(self $spelling), &relative))
      sym.binding_facts[self_key] = relative;
  }
  if (sym.compiler.source_facts) {
    List source_key = %(${scope.symbols} $key);
    sym.binding_facts[%(src-key $binding)] = source_key;
    Var declaration;
    if (sym.compiler.source_primary && !sym.compiler.shallow &&
        sym.compiler.source_declarations.try_get(source_key, &declaration))
      sym.compiler.source_definitions[binding] = declaration;
  }
  return binding;
}

/* A declared `Var T.var(T)` is the conformance marker that lets a named
   type box like a builtin. Keep its tag and exact converter in the active
   translation unit rather than the process-lifetime builtin table. */
static String _declared_var_converter_owner(List key, List type) {
  match (type)
    case %((func (((!is ?named type string)))) "Var"): {
      String owner = named.str(), converter = %"${owner}_var";
      match (key)
        case %((!is ?spelling type string)):
          return spelling.str() == converter ? owner : NULL;
    }
  return NULL;
}

static void _seed_declared_var_tag(List key, List type) {
  String owner = _declared_var_converter_owner(key, type);
  if (!owner) return;
  String converter = %"${owner}_var", Type declared = %($owner);
  declared.register_var_tag(owner, converter);
}

/** Registers declared `T_var` converters in the active `Type` unit. */
void Sym.seed_var_tags(Sym sym, Map symbols) {
  if (!symbols) return;
  foreach (Var (key, type), symbols)
    if (key is <list> && type is <list>) _seed_declared_var_tag(key, type);
}

/** Defines `key` and returns its stable binding in the active scope. */
List Sym.define(Sym sym, List key, List type) {
  SymScope *scope = _semantic_scope(sym, -1);
  sym.set(key, type);
  _seed_declared_var_tag(key, type);
  return _semantic_scope_binding(sym, scope, key);
}

/** Defines `key` in the unit's writable base scope and returns its binding.

    The definition survives the expression scope that first resolved it.
*/
List Sym.define_global(Sym sym, List key, List type) {
  SymScope *scope = _semantic_scope(sym, sym.base_scopes - 1);
  scope.symbols[key] = type;
  _seed_declared_var_tag(key, type);
  return _semantic_scope_binding(sym, scope, key);
}

/** Returns `key`'s type without package fallback, or `NULL`. */
List Sym.get_exact(Sym sym, List key) {
  Var val;
  for (int i = (int) sym.scopes.len() - 1; i >= 0; i--) {
    Map scope = _semantic_scope(sym, i).symbols;
    if (scope.try_get(key, &val)) return val;
  }
  if (_retained_aggregate_member(key) &&
      sym.binding_facts.try_get(%(aggfact $key), &val)) return val;
  return NULL;
}

/* Package files may reference their own file-scope names bare. A plain-key
   total miss retries the package-prefixed key; exact entries win, and
   units outside package mode never retry. */
static List _package_retry_key(Sym sym, List key) {
  String package = sym.compiler.package;
  if (!package || !key || key.cdr() || key.car() is not <string>) return NULL;
  String spelling = key.car().str();
  String prefixed = sym.compiler.package_spelling(spelling);
  return prefixed == spelling ? NULL : %($prefixed);
}

/** Returns `key`'s type, retrying a bare key in package space, or `NULL`. */
List Sym.get(Sym sym, List key) {
  List found = sym.get_exact(key);
  if (found) return found;
  List retry = _package_retry_key(sym, key);
  return retry ? sym.get_exact(retry) : NULL;
}

static List _semantic_lookup(
  Sym sym, List key, List *type, int first, int forward) {
  Var found;
  for (int i = first; i >= 0; i--) {
    SymScope *scope = _semantic_scope(sym, i);
    if (scope.symbols.try_get(key, &found)) {
      if (type) *type = found;
      return _semantic_scope_binding(sym, scope, key);
    }
    if (scope.bindings.try_get(key, &found)) {
      if (type) *type = NULL;
      return found;
    }
  }
  List retry = _package_retry_key(sym, key);
  if (retry && (!forward || sym.get_exact(retry)))
    return _semantic_lookup(sym, retry, type, first, forward);
  if (type) *type = NULL;
  return forward
       ? _semantic_scope_binding(sym, _semantic_scope(sym, -1), key)
       : NULL;
}

/** Resolves an existing key and optionally stores its semantic type.

    A symbol row without a binding receives a stable binding identity. A total
    miss returns `NULL` and stores `NULL` through `type` when provided.
*/
List Sym.lookup(Sym sym, List key, List *type) =>
  _semantic_lookup(sym, key, type, (int) sym.scopes.len() - 1, 0);

/** Resolves `key` or creates a forward binding in the current scope.

    Stores `NULL` through `type` when no declaration supplies a type.
*/
List Sym.reference(Sym sym, List key, List *type) =>
  _semantic_lookup(sym, key, type, (int) sym.scopes.len() - 1, 1);

/** Resolves a binding through base scopes and optionally stores its type.

    Returns `NULL` when no base scope contains the key.
*/
List Sym.resolve_global(Sym sym, List key, List *type) =>
  _semantic_lookup(sym, key, type, sym.base_scopes - 1, 0);

/** Reports whether `binding` belongs to a scope inside the base scopes. */
int Sym.binding_is_local(Sym sym, List binding) =>
  sym.binding_is_local_before(binding, sym.scopes.len());

/** Reports whether `binding` belongs to a local scope below `scope_count`.

    Counts beyond the current scope depth are clamped to that depth.
*/
int Sym.binding_is_local_before(Sym sym, List binding, int scope_count) {
  if (scope_count > (int) sym.scopes.len()) scope_count = sym.scopes.len();
  for (int i = scope_count - 1;
       i >= sym.base_scopes; i--)
    foreach (Var (_, candidate), _semantic_scope(sym, i).bindings)
      if (List.equal(candidate, binding)) return 1;
  return 0;
}

/** Allocates a fresh binding identity for a compiler-introduced spelling. */
List Sym.introduce(Sym sym, String spelling) =>
  _semantic_new_binding(sym, %($spelling));

// A source declaration may not enter the compiler's generated-name space.
// Checked once per declaration; no prepass over the token stream.
static int _is_reserved_spelling(String s) {
  if (!s) return 0;
  if (s.startswith("_x2c_")) return 1;
  if (s == %"_init_guard_") return 1;
  if (s == %"_file_init_") return 1;
  if (s.len() < 2 || s[0] != '_') return 0;
  for (int i = 1; i < s.len(); i++) if (s[i] < '0' || s[i] > '9') return 0;
  return 1;
}

// The declared spelling, when the key names one.  Aggregate keys carry the
// tag in their second slot; anonymous aggregates carry a gensym list there
// and are not source spellings.
static String _declared_spelling(List key) {
  Var (head, tag) = key;
  if (head is <string>) return head.str();
  if (head == <struct> || head == <union> || head == <enum>)
    if (tag is <string>) return tag.str();
  return NULL;
}

/** Returns a name in the current package namespace, preserving prefixes.

    Idempotence lets parsing and declaration rewrites share this operation.
*/
String Compiler.package_spelling(Compiler compiler, String name) {
  if (!compiler.package || !name) return name;
  String prefix = %"${compiler.package}__";
  return name.startswith(prefix) ? name : %"$prefix$name";
}

/* An alias and a `with` name each claim one local spelling. Rebinding that
   spelling, or taking one a declaration already uses, is the same conflict.
   Both messages name what the developer wrote. */
static void _check_package_binding(
  Compiler c, String kind, String local, Token token) {
  Var alias = c.package_aliases[local];
  Var member = c.package_members[local];
  String bound = alias is void ? NULL : alias.string();
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

/** Registers one local package alias.

    Shallow collection and full parsing both see an import, so repeating the
    same package and alias is a no-op. Another binding of the local spelling
    is a parse error.
*/
void Compiler.register_package_alias(
  Compiler compiler, String name, String alias, Token token) {
  Var bound = compiler.package_aliases[alias];
  if (bound is not void && bound.string() == name) return;
  _check_package_binding(compiler, "alias", alias, token);
  compiler.package_aliases[alias] = name;
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
  List packages = NULL;
  foreach (Var (key, root), c.package_roots) {
    String package = key.str();
    if (c.sym.get_exact(%("${package}__$name")))
      packages = cons(package, packages);
  }
  return packages.sort();
}

/** Returns an unambiguous imported spelling for `name`, or `NULL`. */
String Compiler.imported_spelling(Compiler compiler, String name) {
  List packages = compiler.imported_providers(name);
  if (!packages || packages.cdr()) return NULL;
  return %"${packages.car().str()}__$name";
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

/* Package mode rewrites file-scope non-static declaration keys into the
   package's `name__` space, so binding spellings, aggregate tags, and
   derived Var converters carry the prefix everywhere they are read.
   Statics keep their spellings (C internal linkage); anonymous aggregate
   gensyms are not source spellings and stay in the compiler's space. */
static List _package_declared_key(Sym sym, List context, List key, List ast) {
  Compiler compiler = sym.compiler;
  if ((int) sym.scopes.len() != sym.base_scopes) return key;
  if (context && !(context === %(typedef))) return key;
  if (ast.type().is_static()) return key;
  Var (head, tag) = key;
  if (head is <string> && !key.cdr())
    return %(${compiler.package_spelling(head.str())});
  if ((head == <struct> || head == <union> || head == <enum>) &&
      key.cdr() && !key.cddr() && tag is <string>)
    return %($head ${compiler.package_spelling(tag.str())});
  return key;
}

/** Analyzes a complete declaration type and installs its stored declared type.

    Returns the declared binding. At file scope this also records static
    visibility; local declarations record automatic-storage and declared-type
    facts. Stored types discard storage and `inline` while retaining `const`,
    `restrict`, and `volatile`.
*/
List Sym.declare(Sym sym, List context, List key, List ast) {
  with sym.compiler {
    if (_.package) key = _package_declared_key(sym, context, key, ast);
    String spelling = _declared_spelling(key);
    if (_is_reserved_spelling(spelling)) {
      String message =
        %"'$spelling' is reserved for compiler-generated names";
      _.report_error(<parse>, message, _.token, NULL);
    }
    String owner = _package_reserved_owner(_, spelling);
    if (owner)
      _.report_error(
        <parse>, %"'$spelling' is reserved for imported package '$owner'",
        _.token, NULL);
  }
  Type ctxkey = %( @context @key ), type = ast.type_from_ast();
  Type declared_type = type;
  // Track file-local globals so the symbol snapshot can exclude them. The
  // storage class is only visible here, before canonicalization strips it.
  if ((int) sym.scopes.len() == sym.base_scopes && !context) {
    if (ast.type().is_static()) sym.statics[(List) ctxkey] = 1;
    else sym.statics.del((List) ctxkey);
  }
  List binding = NULL;
  if (context === %(typedef)) binding = sym.define(key, (List) ctxkey);
  // A tagged definition also publishes its tag unless the key is that tag.
  if (type.is_aggregate_tag_body() && !ctxkey.is_aggregate_tag()) {
    Var (aggregate, tag) = ast;
    type = %( $aggregate $tag );
  }
  type = type.declared();
  if (!binding) binding = sym.define(ctxkey, (List) type);
  else {
    sym.set(ctxkey, (List) type);
    if (type.is_aggregate_tag() &&
        (int) sym.scopes.len() > sym.base_scopes)
      sym.binding_facts[%(ntype $binding)] = type;
    if ((int) sym.scopes.len() > sym.base_scopes)
      sym.binding_facts[%(emitted $binding)] =
        sym.compiler.fresh_name("local_typedef");
  }
  if (!context && (int) sym.scopes.len() > sym.base_scopes) {
    sym.binding_facts[%(automatic $binding)] = 1;
    sym.binding_facts[%(type $binding)] = declared_type;
    List global_type = NULL;
    sym.resolve_global(key, &global_type);
    if (_declared_var_converter_owner(key, global_type) &&
        !sym.binding_facts.contains(%(emitted $binding)))
      sym.binding_facts[%(emitted $binding)] =
        sym.compiler.fresh_name("var_converter_shadow");
  }
  return binding;
}

/** Installs an existing binding with `ast`'s qualifier-preserving type. */
List Sym.bind_identity(Sym sym, List context, List binding, List ast) {
  String spelling = binding_identity_spelling(binding);
  List key = context ? %(@context $spelling) : %($spelling);
  SymScope *scope = _semantic_scope(sym, -1);
  Type annotation = ast.type_from_ast();
  scope.symbols[key] = annotation.declared();
  if (context === %(typedef)) {
    key = %($spelling);
    scope.symbols[key] = %(typedef $spelling);
    if (annotation.is_aggregate_tag() &&
        (int) sym.scopes.len() > sym.base_scopes)
      sym.binding_facts[%(ntype $binding)] = annotation;
    if ((int) sym.scopes.len() > sym.base_scopes)
      sym.binding_facts[%(emitted $binding)] =
        sym.compiler.fresh_name("local_typedef");
  }
  scope.bindings[key] = binding;
  if (!context && (int) sym.scopes.len() > sym.base_scopes) {
    sym.binding_facts[%(automatic $binding)] = 1;
    sym.binding_facts[%(type $binding)] = annotation;
  }
  return binding;
}

static Type _function_contract_type(Type type, int keep_qualifiers) {
  Array result = %[];
  foreach (Var item, type) {
    if (item is <list>) {
      result.push(
        _function_contract_type(item.list(), keep_qualifiers));
      continue;
    }
    if (item is <symbol>) {
      Symbol symbol = item;
      if (symbol.is_storage_class() ||
          (!keep_qualifiers && symbol.is_type_qualifier()) ||
          symbol.is_inline())
        continue;
    }
    result.push(item);
  }
  return result.list_free();
}

static List _function_completion_contract(
  Type type, List method_identity, List self_signature) {
  Symbol linkage = type.is_static() ? <static> : <extern>;
  List contract = %(
    function-contract
    ${_function_contract_type(type, 0)}
    ${_function_contract_type(type, 1)}
    $linkage
    $method_identity
  );
  return self_signature ? contract.append(%($self_signature)) : contract;
}

static List _binding_method_identity(Compiler compiler, List binding) {
  Var stored;
  return compiler.semantic_binding_facts().try_get(
    %(method $binding), &stored) ? stored.list() : NULL;
}

static List _binding_self_signature(Compiler compiler, List binding) {
  Var stored;
  return compiler.semantic_binding_facts().try_get(
    %(self $binding), &stored) ? stored.list() : NULL;
}

// Record only prototypes reached in positioned full-parse source order.
static void _record_function_prototypes(
  Compiler c, Type declared_type, List items) {
  foreach (List target, items)
    match (target)
      case %(bind ?binding *): {
        List single = %(declare $declared_type (bindings $target));
        Type type = single.type_from_ast();
        if (!type.is_function()) continue;
        List contract = _function_completion_contract(
          type, _binding_method_identity(c, binding),
          _binding_self_signature(c, binding));
        Var stored;
        if (c.semantic_binding_facts().try_get(
          %(completion $binding), &stored)) {
          List state = stored;
          Var (state_kind, prior_contract) = state;
          if (state_kind == <definition> || state_kind == <completed>)
            continue;
          if (state_kind != <prototype> ||
              !List.equal(prior_contract, contract)) {
            c.semantic_binding_facts()[%(completion $binding)] =
              %(conflict);
            continue;
          }
        }
        c.semantic_binding_facts()[%(completion $binding)] =
          %(prototype $contract);
      }
}

static void _record_function_definition(
  Compiler c, Type type, List binding) {
  List contract = _function_completion_contract(
    type, _binding_method_identity(c, binding),
    _binding_self_signature(c, binding));
  Var stored;
  if (c.semantic_binding_facts().try_get(
    %(completion $binding), &stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    String spelling = binding_identity_spelling(binding);
    if (state_kind == <prototype>) {
      if (List.equal(prior_contract, contract)) {
        c.semantic_binding_facts()[%(completion $binding)] =
          %(completed $contract);
        return;
      }
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
    if (state_kind == <definition> || state_kind == <completed>)
      c.report_error(
        <type>, %"function '$spelling' is already defined in this scope",
        c.token, %("prior definition: '$spelling'"));
  }
  c.semantic_binding_facts()[%(completion $binding)] =
    %(definition $contract);
  String spelling = binding_identity_spelling(binding);
  if (spelling && !type.is_static()) c.fn_defs[spelling] = 1;
}

static int _is_initializable_object_type(Compiler compiler, Type type) =>
  compiler.sym.is_string_type(type) ||
         compiler.sym.is_named_value_type(type, "List") ||
         compiler.sym.is_array_type(type) ||
         compiler.sym.is_map_type(type) ||
         compiler.sym.is_named_value_type(type, "Func");

static void _collect_initializer_references(
  Var value, Map references, List *ordered) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node)
    case %(input *arguments): {
      foreach (List argument, arguments)
        _collect_initializer_references(argument.cadr(), references, ordered);
      return;
    }
  match (node)
    case %(indexinit ? ?initializer): {
      _collect_initializer_references(initializer, references, ordered);
      return;
    }
  match (node)
    case %(expr (!set ?type (*))
           (ident (!set ?binding (binding ? ?)))): {
      if (!type.type().is_function()) {
        if (!references.contains(binding)) *ordered = cons(binding, *ordered);
        references[binding] = 1;
      }
      return;
    }
  foreach (Var child, node)
    _collect_initializer_references(child, references, ordered);
}

static void _record_static_object_declaration(
  Compiler c, Type declared, List bindings) {
  if (!declared.is_static()) return;
  int declared_var = c.sym.is_var_type(declared);
  if (!declared_var &&
      !_is_initializable_object_type(c, declared)) return;
  foreach (List binding_init, bindings)
    match (binding_init)
      case %(op = (bind (!set ?binding (binding ? ?)) ?)
             (expr (!set ?initializer_type (*)) ?value)): {
        if (declared_var && !_is_initializable_object_type(
          c, initializer_type))
          continue;
        Map references = %{}, List ordered = NULL;
        _collect_initializer_references(value, references, &ordered);
        c.static_init_deps[binding] = ordered.reverse();
      }
}

static void _validate_static_object_initializers(Compiler compiler) {
  Map statics = compiler.sym.file_statics();
  foreach (Var (key, value), compiler.static_init_deps) {
    List binding = key, dependencies = value;
    foreach (List reference, dependencies) {
      String name = binding_identity_spelling(reference);
      if (!name || statics.contains(%($name))) continue;
      String target = binding_identity_spelling(binding);
      Token token = NULL;
      Var token_index;
      if (compiler.init_tokens.try_get(binding, &token_index)) {
        Token tokens = compiler.tokenizer.tokens;
        token = tokens + token_index.integer();
      }
      compiler.report_error(
        <parse>,
        %"file-static x2c initializer depends on non-static '$name'",
        token, target ? %("initializer: $target") : NULL);
    }
  }
}

static void _record_top_level_function_state(Compiler compiler, List node) {
  match (node) {
    case %(declare (!set ?declared (*)) (bindings *bindings)): {
      Type type = declared;
      _record_static_object_declaration(compiler, type, bindings);
      _record_function_prototypes(compiler, type, bindings);
    }
    case %(function ?return_type
           (!set ?target (bind ?binding *)) ?): {
      List declaration = %(declare $return_type (bindings $target));
      _record_function_definition(
        compiler, declaration.type_from_ast(), binding);
    }
  }
}

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

// The resolver cannot tell a true cycle from an absurdly long chain, so the
// diagnostic states only what it can determine. `typedef Color Color;` is
// legal C; it binds ("Color") to (typedef "Color") and back, so cycles are
// real.
static void _typedef_budget_error(Sym sym, Type origin) {
  String message =
    %"typedef chain too deep (possible cycle) resolving ${origin.repr()}";
  sym.compiler.report_error(<type>, message, NULL, NULL);
}

// Resolve a typedef chain, optionally stopping at a semantic type
// identity.  origin is the type the caller asked about, kept only so an
// over-budget walk can name it instead of some mid-chain link.
static Type _resolve_key_helper(
  Sym sym, Type key, Type stop, Type origin, int hops) {
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(sym, origin);
  if (stop && key == stop) return key;
  if (key.is_typedef_name() || key.is_typedef()) {
    Type type = _typedef_target(sym, key);
    if (type) return _resolve_key_helper(sym, type, stop, origin, hops + 1);
  }
  match (key) case %((!set ?kind (!or struct union))
      (binding ? ?spelling)):
    if (!sym.field_order(key)) return %($kind $spelling);
  return key;
}

/** Resolves a canonical typedef key to the end of its declared chain. */
Type Sym.resolve_key(Sym sym, Type key) {
  if (!key) return key;
  key = key.canonicalize();
  return _resolve_key_helper(sym, key, NULL, key, 0);
}

/** Resolves one typedef hop and counts against the shared cycle budget.

    `hops` is an in-out counter initialized by the caller for the whole walk.
    Returns `NULL` for an unresolved link. The shared budget turns a cycle
    into the same diagnostic as full-chain resolution.
*/
Type Sym.next_typedef(Sym sym, Type type, int *hops) {
  if (++*hops > RESOLVE_KEY_MAX_HOPS) {
    _typedef_budget_error(sym, type);
    return NULL;
  }
  return type.is_typedef_name() || type.is_typedef()
       ? _typedef_target(sym, type) : sym.get(type);
}

/* Angle-included system typedefs have no collected binding. These canonical
   LP64 forms match Type.scalar and are consulted only after source typedef
   resolution, so a source declaration wins. int64_t maps to long to retain
   the native long Var identity.

   The labels are encoded Symbols, not the C spellings, and the subject is
   `name.symbol()`, the same encoding applied to the source identifier.
   A C name that outruns the Symbol capacity therefore appears here in the
   form it encodes to: `size_t` is `<size-t>`, since the 5-bit alphabet
   folds the separator, and `uint16_t` is `<uint16_>`, since a digit forces
   the seven-byte form. `uint8_t` and `int16_t` fit and keep their
   spelling. */
static Type _builtin_typedef_scalar(Type key) {
  if (!key.is_bare_typedef_name()) return NULL;
  String name = key.car().str();
  switch (name.symbol()) {
    case <u8>: case <uint8_t>: return %(unsigned char);
    case <i8>: case <int8_t>: return %(signed char);
    case <u16>: case <uint16_>: return %(unsigned short);
    case <i16>: case <int16_t>: return %(short);
    case <u32>: case <uint32_>: return %(unsigned);
    case <i32>: case <int32_t>: case <wchar-t>: return %(int);
    case <u64>: case <uint64_>: case <uintptr-t>:
    case <size-t>: return %(unsigned long);
    case <i64>: case <int64_t>: case <intptr-t>: case <ptrdiff-t>:
    case <ssize-t>: case <off-t>: case <time-t>: return %(long);
    case <u128>: return %(unsigned long long);
    case <i128>: return %(long long);
    case <f32>: return %(float);
    case <f64>: return %(double);
    case <f128>: return %(long double);
  }
  return NULL;
}

/** Resolves a numeric typedef without reducing semantic object types.

    Returns `NULL` when resolution yields neither a numeric type nor a
    recognized builtin numeric typedef.
*/
Type Sym.resolve_numeric_type(Sym sym, Type type) {
  Type scalar = type.scalar();
  if (scalar) return scalar;
  Type resolved = sym.resolve_key(type);
  if (resolved.is_number()) return resolved;
  return _builtin_typedef_scalar(resolved);
}

static Type _replace_type_base(Type type, Type base, Type replacement) {
  if (type === base) return replacement;
  if (!type) return type;
  return cons(type.car(), _replace_type_base(type.cdr(), base, replacement));
}

/** Resolves a block-local typedef to the type saved at its declaration.
    File-scope names retain their semantic identity. Local alias definitions
    are resolved before they are installed, so one lookup crosses the whole
    local chain without consulting names shadowed since its declaration.
*/
Type Sym.local_type(Sym sym, Type type) {
  Type base = type.base_type();
  if (base.is_aggregate_tag() && base.cadr() is <string>) {
    for (int i = sym.scopes.len() - 1; i >= sym.base_scopes; i--) {
      SymScope *scope = _semantic_scope(sym, i);
      Var binding;
      if (scope.bindings.try_get(base, &binding))
        return _replace_type_base(type, base, %(${base.car()} $binding));
    }
    return type;
  }
  if (!base.is_bare_typedef_name()) return type;
  for (int i = sym.scopes.len() - 1; i >= sym.base_scopes; i--) {
    Map symbols = _semantic_scope(sym, i).symbols;
    Var marker;
    if (!symbols.try_get(base, &marker)) continue;
    Type declared = marker.type();
    if (!declared.is_typedef()) return type;
    Var target;
    if (!symbols.try_get(declared, &target)) return type;
    return _replace_type_base(type, base, target.type());
  }
  return type;
}

/** Binds a local aggregate tag before its fields, preserving native spelling.
    A reference reuses the nearest visible tag; a definition or standalone
    forward declaration introduces the tag in the current lexical scope.
*/
Var Compiler.aggregate_name(
  Compiler compiler, Symbol kind, Var name, int definition) {
  Sym sym = compiler.sym;
  if (compiler.macro_holes || name is not <string> ||
      (int) sym.scopes.len() <= sym.base_scopes) return name;
  Type type = %($kind $name);
  if (!definition && sym.get_exact(type))
    return sym.local_type(type).cadr();
  if (!definition && compiler.shallow) return name;
  List binding = sym.current_binding(type);
  if (!binding) binding = sym.declare(NULL, type, type);
  return binding;
}

/* Semantic types contain no local aliases. A retained file type's spelling
   must keep its meaning when an inner declaration shadows that spelling. */
static Type _typedef_target(Sym sym, Type key) {
  for (int i = sym.base_scopes - 1; i >= 0; i--) {
    Var target;
    if (_semantic_scope(sym, i).symbols.try_get(key, &target)) return target;
  }
  return NULL;
}

static Type _normalize_declared_type(
  Sym sym, Type type, Type origin, int hops) {
  type = type.declared();
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(sym, origin);
  Type base = type.base_type();
  if (base && (base.is_typedef_name() || base.is_typedef())) {
    Type next = _typedef_target(sym, base);
    if (!next) next = _builtin_typedef_scalar(base);
    if (next)
      return _normalize_declared_type(
        sym, _replace_type_base(type, base, next), origin, hops + 1);
  }
  return type;
}

/** Resolves typedef bases while retaining every declarator qualifier. */
Type Sym.normalize_declared_type(Sym sym, Type type) =>
  type ? _normalize_declared_type(sym, type, type, 0) : NULL;

static Symbol _var_tag_for_type_helper(
  Sym sym, Type type, Type origin, Type *resolved, int hops) {
  type = type.canonicalize();
  Symbol tag = type.var_tag();
  if (tag) {
    if (resolved) *resolved = type;
    return tag;
  }
  if (hops > RESOLVE_KEY_MAX_HOPS) _typedef_budget_error(sym, origin);
  Type base = type.base_type();
  if (base && (base.is_typedef_name() || base.is_typedef())) {
    Type next = _typedef_target(sym, base);
    if (!next) next = _builtin_typedef_scalar(base);
    if (next) {
      Type replaced = _replace_type_base(type, base, next);
      return _var_tag_for_type_helper(
        sym, replaced, origin, resolved, hops + 1);
    }
  }
  if (resolved) *resolved = type;
  return 0;
}

/** Returns a type's `Var` tag and optionally stores its resolved type.

    `resolved` receives the final type even when the result is zero because no
    `Var` tag is registered. A null input stores `NULL` and returns zero.
*/
Symbol Sym.var_tag_for_type(Sym sym, Type type, Type *resolved) {
  if (!type) {
    if (resolved) *resolved = NULL;
    return 0;
  }
  Type origin = type.canonicalize();
  return _var_tag_for_type_helper(sym, origin, origin, resolved, 0);
}

/** Reports whether `type` reaches the named `Var` value type. */
int Sym.is_var_type(Sym sym, Type type) =>
  sym.is_named_value_type(type, "Var");

/** Reports whether `type` reaches the named `String` value type. */
int Sym.is_string_type(Sym sym, Type type) =>
  sym.is_named_value_type(type, "String");

/** Reports whether `type` reaches the named `Array` value type. */
int Sym.is_array_type(Sym sym, Type type) =>
  sym.is_named_value_type(type, "Array");

/** Reports whether `type` reaches the named `Map` value type. */
int Sym.is_map_type(Sym sym, Type type) =>
  sym.is_named_value_type(type, "Map");

/** Reports whether `type` reaches a named value type before its definition. */
int Sym.is_named_value_type(Sym sym, Type type, String name) {
  // Stop at the named type instead of resolving through its typedef.
  if (!type || !name) return 0;
  Type wanted = %($name), origin = type.canonicalize();
  type = _resolve_key_helper(sym, origin, wanted, origin, 0);
  return type == wanted;
}

/** Returns an aggregate field's declared type, or `NULL`. */
Type Sym.lookup_field(Sym sym, Type type, List field) {
  type = sym.resolve_key(type);
  if (!type || !type.is_aggregate_tag()) return NULL;
  field = %( @type @field );
  return sym.get(field);
}

/** Records declaration AST fields in source order after binding finishes.

    `Field` types already use member keys. Unnamed rows retain their type
    and an empty name so initializer traversal preserves anonymous subobjects.
*/
void Sym.declare_field_order(Sym sym, Type type, List fields) {
  Array rows = %[];
  foreach (List declaration, fields) {
    while (declaration.car() == <at>) declaration = declaration.caddr();
    if (declaration.car() == <c-assert>) continue;
    List bindings = declaration.caddr();
    foreach (List declarator, bindings.cdr()) {
      String name = binding_identity_spelling(declarator.cadr());
      Type declared = name ? sym.get(%(@type $name))
        : %(declare ${declaration.cadr()} (bindings $declarator))
          .type_from_ast().declared();
      rows.push(%($name $declared));
    }
  }
  sym.set(%(@type "field-order"), %(fields @{rows.list_free()}));
}

/** Returns recorded fields in source order, or `NULL`. */
List Sym.field_order(Sym sym, Type type) => sym.get(%(@type "field-order"));

/** Marks one named aggregate field as a delegate. */
void Sym.declare_delegate_field(Sym sym, Type aggregate, String name) {
  sym.set(%(@aggregate delegate $name), %(delegate));
}

/** Resolves typedefs or one pointer layer to an aggregate tag, or `NULL`. */
Type Sym.delegate_aggregate(Sym sym, Type type) {
  type = type.canonicalize();
  int hops = 0;
  while (type && !type.is_aggregate_tag()) {
    if (type.is_pointer()) {
      type = sym.resolve_key(type.dereference());
      break;
    }
    type = sym.next_typedef(type, &hops);
  }
  return type && type.is_aggregate_tag() ? type : NULL;
}

/** Returns a fresh semantic identity for an anonymous aggregate. */
List Compiler.gensym(Compiler compiler) {
  compiler.names.gensym_count++;
  return %((gensym ${compiler.names.gensym_count}));
}

/** Sets the shared anonymous-aggregate counter used before the next result. */
void Compiler.set_gensym(Compiler compiler, int count)
  { compiler.names.gensym_count = count; }

/** Pushes a new empty lexical scope. */
void Sym.push_new_scope(Sym sym) {
  struct SymScope scope = {
    .symbols = %{},
    .bindings = %{},
    .enumerators = %{}
  };
  sym.scopes.push(&scope);
}

/** Pushes a caller-supplied lexical scope while retaining its map objects. */
void Sym.push_scope(Sym sym, SymScope scope) {
  sym.scopes.push(&scope);
}

/** Pops the innermost scope, or returns an empty scope when none exists. */
SymScope Sym.pop_scope(Sym sym) {
  struct SymScope scope = { 0 };
  sym.scopes.try_pop(&scope);
  if ((void *) scope.macros != NULL)
    sym.local_macro_names -= scope.macros.len();
  return scope;
}

// constructed ast elaboration
