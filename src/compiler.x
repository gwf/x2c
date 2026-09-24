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
  int source_syntax;
  Map local_macro_captures;
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
  /* Which `meta` functions a constant-argument call may answer from the
     compile-time form. `meta_folds` holds the binding ids this compiler
     declared, so a macro import's own compiler keeps its entries and no unit
     folds a call another unit's emission designates. `meta_impure` names the
     functions that reach file-scope or static state, opaque native effects,
     or enum representation the evaluator cannot prove equal to C; it is
     shared with an import's compiler, which installs into the same session.
     `meta_comptime` names the ones that reach a `Meta` operation and so have
     no runtime form at all: no unit emits one and no call to one folds.
     `meta_regions` maps each installed one to its region summary, which
     the lifetime check of a later `meta` function reads at its calls. */
  Map meta_folds, meta_impure, meta_comptime, meta_regions;
  /* File-scope values and types explicitly advertised to the compile-time
     evaluator. `meta_values` is keyed by binding id and stores
     `(MUTABLE LAYOUT)` for the object. */
  Map meta_values;
  /* Canonical struct Type -> its compile-time byte layout, a cache that
     semantic transactions roll back with the declarations it describes. */
  Map meta_layouts;
  /* Native functions that included units advertise with `meta`, by name,
     holding each declared signature. A function binds into the macro
     session the first time lowered code calls it. */
  Map native_meta;
  int runtime_inc, runtime_hdrs, collect_protocols, shallow, source_private;
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

List Compiler.lift_func_expression(Compiler compiler, List expression);

#include "utils.x"
#include "parse.x"
#include "protocol.x"
#include "macros.x"
#include "comptime.x"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/** Merges one translation dependency, preserving an existing content hash. */
void Map.merge_translation_dependency(Map m, String path, Var content_hash) {
  if (content_hash is <string>) {
    if (m[path] is not <string>) m[path] = content_hash;
  }
  else m.setdefault(path, 1);
}

/** Records a path dependency not embedded in generated C. */
void Compiler.add_translation_dependency(Compiler compiler, String path) {
  compiler.deps.merge_translation_dependency(path, 1);
}

/** Merges another translation's dependency rows into this compiler. */
void Compiler.merge_translation_dependencies(Compiler c, Map dependencies) {
  foreach (Var (path, content_hash), dependencies)
    c.deps.merge_translation_dependency(path, content_hash);
}

// compiler lifecycle

typedef struct Sym {
  Block scopes, Map globals, statics, binding_facts;
  int base_scopes, local_macro_names;
  // Owning compiler, so type resolution can report its own diagnostics.
  Compiler compiler;
} *Sym;

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
  Compiler compiler = ptr;
  compiler.free_lisp();
}

/** Routes this compiler's diagnostic store through its own printer.

    Compilers that share a store call this when taking the diagnostic stream
    back from another compiler.
*/
void Compiler.own_diagnostics(Compiler compiler) {
  compiler.diagnostics.printer = compiler;
}

/** Shares a caller's diagnostic stream while preserving its emission policy.
    The caller restores the saved printer after this child finishes.
*/
void Compiler.borrow_diagnostics(Compiler compiler, Compiler owner) {
  compiler.diagnostics = owner.diagnostics;
  if (compiler.diagnostics.printer) compiler.own_diagnostics();
}

/** Shares the symbol table, literal cache, and protocol registries of the
    unit `owner` is translating, so a child that binds declarations binds
    them into that unit. A `meta` definition in a macro import is bound here
    and emitted by `owner`, so both compilers must read one table: its
    `(cache id)` references index `owner`'s keys, and its operations resolve
    through `owner`'s protocol rows. Both install into one macro session, so
    they also read one record of which `meta` functions reach file-scope
    state.
*/
void Compiler.borrow_unit_semantics(Compiler compiler, Compiler owner) {
  compiler.sym = owner.sym;
  compiler.fn_defs = owner.fn_defs;
  compiler.id_keys = owner.id_keys;
  compiler.key_ids = owner.key_ids;
  compiler.protocols = owner.protocols;
  compiler.adoptions = owner.adoptions;
  compiler.conforms = owner.conforms;
  compiler.protocol_helpers = owner.protocol_helpers;
  compiler.proto_cache = owner.proto_cache;
  compiler.meta_impure = owner.meta_impure;
  compiler.meta_comptime = owner.meta_comptime;
  compiler.meta_regions = owner.meta_regions;
  compiler.meta_values = owner.meta_values;
  compiler.meta_layouts = owner.meta_layouts;
  compiler.native_meta = owner.native_meta;
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

/** Retains a child's final diagnostics and closes its owned Lisp session. */
void Compiler.close_child(Compiler compiler, Compiler child) {
  compiler.take_diagnostics(child);
  child.free_lisp();
}

// Zero finalizer-visible state before any fallible initialization.
static Compiler _new(Compiler owner) {
  Compiler compiler =
    Scope.malloc_finalized(sizeof(struct Compiler), _drop_compiler);
  memset(compiler, 0, sizeof(struct Compiler));
  with compiler {
    _.id_keys = [];
    _.key_ids = {};
    _.deps = {};
    _.macros = {};
    _.kw_aliases = {};
    _.kw_seen = {};
    _.object_macros = {};
    _.proto_cache = {};
    _.imports = {};
    _.init_tokens = {};
    _.static_init_deps = {};
    _.fn_defs = {};
    _.meta_folds = {};
    _.meta_impure = {};
    _.meta_comptime = {};
    _.meta_regions = {};
    _.meta_values = {};
    _.meta_layouts = {};
    _.native_meta = {};
    if (!owner) _.inherit_shared_meta();
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
      _.declaration_produced = owner.declaration_produced;
      _.source_facts = owner.source_facts;
      _.source_occurrences = owner.source_occurrences;
      _.source_definitions = owner.source_definitions;
      _.source_declarations = owner.source_declarations;
      _.source_texts = owner.source_texts;
      _.unit_script = owner.unit_script;
      _.include_dirs = owner.include_dirs;
    }
    else {
      _.package_roots = {};
      _.package_aliases = {};
      _.package_members = {};
      _.names = Scope.calloc(1, sizeof(struct GenNames));
      _.names.counters = {};
      _.names.adapters = {};
      _.names.file_scope_owners = {};
    }
    _.sym = Scope.calloc(1, sizeof(struct Sym));
    with _.sym {
      _.compiler = compiler;
      _.binding_facts = {};
      _.scopes = Block.new(sizeof(SymScope));
      _.statics = {};
    }
    _.inits = [];
    _.early_decls = [];
    _.meta_defs = [];
    _.collect_protocols = 1;
    _.diagnostics = Diagnostics.new(
      owner && owner.diagnostics.printer ? _ : NULL,
      owner ? owner.diagnostics.limit : 1);
    _.braces = [];
    _.import_stack = [];
    _.origins = [];
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

/** Takes over `owner`'s macro, object-like `#define`, import, keyword, and
    Lisp state for one segment of a collected file. Segments are one
    translation unit, so a shadow uses the unit's Lisp environment rather
    than its own.
*/
void Compiler.take_unit_state(Compiler compiler, Compiler owner) {
  compiler.macros = owner.macros;
  compiler.object_macros = owner.object_macros;
  compiler.imports = owner.imports;
  compiler.kw_aliases = owner.kw_aliases;
  compiler.kw_seen = owner.kw_seen;
  compiler.macro_lisp = owner.macro_lisp;
  compiler.declaration_effects = owner.declaration_effects;
  compiler.borrowed_lisp = compiler.macro_lisp != NULL;
}

/** Returns that state to `owner`, so the next segment starts where this one
    finished and any Lisp environment this segment created stays alive after
    the shadow is released.
*/
void Compiler.return_unit_state(Compiler compiler, Compiler owner) {
  owner.macros = compiler.macros;
  owner.object_macros = compiler.object_macros;
  owner.imports = compiler.imports;
  owner.kw_aliases = compiler.kw_aliases;
  owner.kw_seen = compiler.kw_seen;
  owner.macro_lisp = compiler.macro_lisp;
  owner.declaration_effects = compiler.declaration_effects;
  owner.declaration_produced |= compiler.declaration_produced;
  compiler.borrowed_lisp = compiler.macro_lisp != NULL;
}

/** Reads a source through the request view and retains exact response
    bytes.
*/
int Compiler.read_source(Compiler c, String path, String volatile *text) {
  if (!c.sources.read(path, text)) return 0;
  if (c.source_facts) c.source_texts[Path.absolute(path)] = *text;
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
    home, otherwise `path`. Interfaces, retained declarations, and generated
    identities spell paths this way, so they do not depend on where the home
    is installed.
*/
String home_portable_path(String path) {
  String prefix = %"${x2c_get_root()}/";
  return path.startswith(prefix) ? path[prefix.len():] : path;
}

/** Returns the absolute path that a `home_portable_path` spelling names. */
String home_absolute_path(String spelling) =>
  spelling.startswith("/") ? spelling : %"${x2c_get_root()}/$spelling";

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
void Compiler.merge_source_declarations(Compiler c, Map target, Map source) {
  if (!c.source_facts) return;
  foreach (Var key, source.keys())
    if (key is <list>) c.copy_source_declaration(target, source, key);
}

static List _source_range(Compiler compiler, Token first, Token after) {
  if (!first || !after || first >= after || compiler.macro_holes) return NULL;
  Token last = after - 1;
  while (last > first &&
         (last.type == <space> || last.type == <comment> ||
          last.type == <preproc>)) last--;
  String path = Path.absolute(compiler.filename);
  if (!compiler.source_texts.contains(path))
    compiler.source_texts[path] = compiler.text;
  return %($path ${first.pos} ${last.pos + last.len});
}

/** Records a physical declaration using the binding's actual scope and key. */
void Compiler.record_source_declaration(
  Compiler c, List binding, Token first, Token after) {
  if (!c.source_facts || c.macro_holes) return;
  Var value;
  if (!c.semantic_binding_facts().try_get(%(src-key $binding), &value)) return;
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

/** Returns the current borrowed semantic-facts map indexed by binding.

    A semantic transaction may replace this map, so reacquire it afterwards.
*/
Map Compiler.semantic_binding_facts(Compiler c) => c.sym.binding_facts;

/** Reports the outer deferred source parser, excluding macro templates. */
int Compiler.parsing_source_syntax(Compiler c) => c.source_syntax &&
  c.macro_holes && c.macro_holes.contains(%(source-ast));

/** Returns the active macro definition's borrowed local map, or `NULL`. */
Map Compiler.macro_definition_locals(Compiler compiler) {
  Var stored = compiler.macro_holes[%(locals)];
  return stored is <map> ? stored : NULL;
}

/** Allocates the next compiler-private C spelling for `stem`.

    Related compilers increment the same per-stem counter, except while a
    macro import is being parsed, which counts separately. An import's `meta`
    bodies are parsed in every unit that imports the file and in none that is
    built from the `.xi` prelude, so a name minted there must not move the
    unit's own counter or the two modes emit different C. Those names carry
    an `m` before the stem, so they cannot collide with the unit's.
*/
String Compiler.fresh_name(Compiler compiler, String stem) {
  String key = compiler.import_src ? %"m$stem" : stem;
  Var stored;
  int count = compiler.names.counters.try_get(key, &stored) ? stored : 0;
  String name = %"_x2c_${key}_${count++}";
  compiler.names.counters[key] = count;
  return name;
}

/** Returns a binding's selected emitted spelling.

    A binding without an explicit emission rename uses its identity spelling.
*/
String Compiler.emitted_binding_name(Compiler compiler, List binding) {
  Var renamed;
  if (compiler.semantic_binding_facts().try_get(%(emitted $binding),
                                                &renamed))
    return renamed;
  return binding_identity_spelling(binding);
}

/* Classifies an opening conditional directive by which of its arms C can
   never reach: `<first>` when the condition requires a never-defined name
   or is `0`, `<rest>` when it is exactly `!defined(NAME)`, else 0. x2c output
   is compiled as C by a GNU-style compiler, so `__cplusplus` and `_MSC_VER`
   are never defined; each reads as `<never>`, which no C token spells. */
static Symbol _never_active_arm(String s) {
  Tokenizer scanned = Tokenizer.new(preproc_directive(s));
  scanned.scan();
  Array words = [];
  for (Token t = _skip_forward(scanned.tokens); t.type != <eof>;
       t = _skip_forward(t + 1))
    words.push(t.text == "__cplusplus" || t.text == "_MSC_VER"
               ? "<never>" : t.text);
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

/* Reports whether the attribute list the group `open` holds names an
   attribute that can change a struct's layout, spelled with or without its
   surrounding underscores. Identifiers inside an attribute's own arguments
   are not names. */
static int _layout_attribute(Token open, int *packed) {
  Token close = open.group_close();
  int depth = 0, layout = 0;
  for (Token t = open; t < close; t++) {
    depth += t.type.group_step();
    if (depth != 1 || t.type != <ident>) continue;
    String word = t.text.strip("_");
    if (word == "packed") {
      layout = 1;
      *packed = 1;
    }
    else if (word == "aligned" || word == "mode" ||
             word == "vector_size") layout = 1;
  }
  return layout;
}

/* Records a pair of layout marks at the attribute starting at token
   `index` when it can change a struct's layout. A source attribute is
   `__attribute__ ((...))`; the preprocessor turns one into
   `__x2c_attribute__ "(...)"` (see Toolchain.preprocess), whose two tokens
   become comments, as though the preprocessor had erased them. Returns the
   index of the attribute's last token. */
static size_t _note_attribute(Compiler c, size_t index) {
  Token base = c.tokenizer.tokens, marker = base + index;
  Token last = _skip_forward(marker + 1);
  int layout = 0, packed = 0;
  if (marker.text == "__attribute__") {
    if (last.type != <(>) return index;
    Token inner = _skip_forward(last + 1);
    last = last.group_close();
    if (last.type == <eof>) return index;
    layout = inner.type == <(> && _layout_attribute(inner, &packed);
  }
  else {
    if (last.type != <lit-char*>) return index;
    marker.type = last.type = <comment>;
    Tokenizer words = Tokenizer.new(String.parse(last.text));
    words.scan();
    Token open = _skip_forward(words.tokens);
    layout = open.type == <(> && _layout_attribute(open, &packed);
  }
  if (packed) {
    c.packed_marks.push((long) index);
    c.packed_marks.push((long) index + 1);
  }
  if (layout) {
    c.layout_marks.push((long) index);
    c.layout_marks.push((long) index + 1);
  }
  return last - base;
}

/* Returns the name token of the `#define` or `#undef` directive `content`,
   or NULL for any other directive, and sets `*undefined` for `#undef`. The
   directive is scanned as x2c tokens. */
static Token _macro_directive(String content, int *undefined) {
  String directive = preproc_directive(content);
  *undefined = directive.startswith("undef");
  if (!*undefined && !directive.startswith("define")) return NULL;
  Tokenizer scanned = Tokenizer.new(
    directive.remove_prefix(*undefined ? "undef" : "define"));
  scanned.scan();
  Token token = _skip_forward(scanned.tokens);
  return token.type == <ident> ? token : NULL;
}

/* Tracks in `layout` the macros whose body holds an attribute that can
   change a struct's layout, written out or through another such macro. A
   use of one is marked as the attribute it expands to would be. As with
   layout, a macro that any arm defines with such an attribute stays in
   `layout`; only an `#undef` or definition outside every conditional group,
   `conditional` false, removes it. */
static void _note_layout_macro(
  String content, Map layout, int conditional) {
  int undefined;
  Token name = _macro_directive(content, &undefined);
  if (!name) return;
  if (!conditional) layout.del(name.text);
  if (undefined) return;
  Token token = name + 1;
  if (token.type == <(>) token = token.after_group();
  int value = 0;
  for (; token.type != <eof>; token = _skip_forward(token + 1)) {
    if (token.type != <ident>) continue;
    if (token.text == "__attribute__") {
      Token open = _skip_forward(token + 1);
      Token inner = open.type == <(> ? _skip_forward(open + 1) : open;
      int packed = 0;
      if (inner.type == <(> && _layout_attribute(inner, &packed))
        value = packed ? 2 : value ? value : 1;
    }
    else if (layout.contains(token.text)) {
      int inherited = layout[token.text];
      if (inherited > value) value = inherited;
    }
  }
  if (value && (!layout.contains(name.text) || layout[name.text] < value))
    layout[name.text] = value;
}

/* Records the open conditional groups after each conditional directive as
   `(id arm state)` entries. x2c output is always compiled as C by a
   GNU-style compiler, so an arm that only C++, MSVC, or `#if 0` reaches
   holds no syntax x2c needs to parse. Its tokens become comments; the
   directives around it stay in place, so emission is unchanged. A group's
   state is 2 while its arm is hidden, 1 when the arms after its first
   `#else` will be, and 0 otherwise.

   The same pass marks layout attributes where written or where a macro
   expands to one. */
static void _scan_conditionals(Compiler c) {
  Array stack = $auto([]);
  Map layout = $auto({});
  int hidden = 0, serial = 0;
  c.arm_stacks = {};
  c.layout_marks = [];
  c.packed_marks = [];
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <eof>) break;
    if (token.type != <preproc>) {
      /* A lexical failure ends the token stream, so the rest of the unit is
         missing whichever arm holds it; the parser reports the `<error>`
         token rather than hiding it. */
      if (hidden && token.type != <space> && token.type != <error>)
        token.type = <comment>;
      else if (token.type == <ident> &&
               (token.text == "__attribute__" ||
                token.text == "__x2c_attribute__"))
        i = _note_attribute(c, i);
      else if (token.type == <ident> && layout.contains(token.text)) {
        c.layout_marks.push((long) i);
        c.layout_marks.push((long) i + 1);
        if (layout[token.text] == 2) {
          c.packed_marks.push((long) i);
          c.packed_marks.push((long) i + 1);
        }
      }
      continue;
    }
    Symbol kind = preproc_conditional_kind(token.text);
    int conditional = kind == <open> || (kind && stack.len());
    if (kind == <open>) {
      Symbol never = _never_active_arm(token.text);
      stack.push(%(${++serial} 0 ${never == <first> ? 2 : never == <rest>}));
    }
    else if (kind == <branch> && stack.len()) {
      Var (id, arm, state) = stack[-1];
      stack[-1] = %($id ${arm.integer() + 1} ${state.integer() == 1 ? 2 : 0});
    }
    else if (kind == <close> && stack.len()) stack.take_last();
    else {
      if (!hidden)
        _note_layout_macro(token.text, layout, stack.len());
    }
    if (!conditional) continue;
    c.arm_stacks[(long) i] = stack.list();
    hidden = 0;
    foreach (List group, stack) if (group.caddr() == 2) hidden = 1;
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

/* `in` and `match` are C identifiers as often as x2c keywords. `in` is the
   operator only between two operands; `match` is the statement only as
   `match (...)` followed by `case` or `{`. Every other occurrence is a
   name, so C that uses them keeps compiling. */
static void _retag_contextual_keywords(Tokenizer tokenizer) {
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

/* A lexical failure truncates the token stream, so the parser reaches the
   appended `<eof>` and blames the end of the file. Report the refused byte
   instead. An `<incomplete>` token really did run out of source, so it keeps
   the end-of-file diagnostic that describes it. */
static void _report_malformed_token(Compiler c) {
  if (c.tokenizer.status() != <malformed>) return;
  for (size_t i = 0; i < c.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) c.tokenizer.tokens)[i];
    if (token.type == <error>)
      c.report_error(<parse>, "invalid token", token, NULL);
  }
}

/** Scans source and positions the compiler at its first non-trivia token.

    The compiler borrows `text` for diagnostics and macro source capture until
    translation finishes.
*/
void Compiler.tokenize(Compiler c, char *text) {
  /* The unit's script settings apply to the one file that carries the
     shebang, whichever compiler reads it. */
  if (c.unit_script && c.filename &&
      (c.filename == c.unit_script.path ||
       Path.absolute(c.filename) == c.unit_script.path))
    c.script = c.unit_script;
  c.input_boundary = NULL;
  c.text = text;
  c.tokenizer = Tokenizer.new(c.text);
  c.tokenizer.scan();
  _report_malformed_token(c);
  _scan_conditionals(c);
  _retag_contextual_keywords(c.tokenizer);
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

/** Retags the token beginning at `position` as a private completion marker. */
void Compiler.mark_completion(Compiler compiler, int position) {
  for (size_t i = 0; i < compiler.tokenizer.tokens.len(); i++) {
    Token token = &((struct Token *) compiler.tokenizer.tokens)[i];
    if (token.pos == position && token.type == <ident>) {
      token.type = <replcomp>;
      return;
    }
  }
}

/** Reports whether the parser is at the private REPL completion marker. */
int Compiler.at_completion(Compiler compiler) =>
  compiler.token.type == <replcomp>;

/* Transfers completion from the grammar production that owns the cursor.
   Rows retain semantic namespace facts; keywords are choices owned by that
   production rather than an editor-side copy of the grammar. */
void Compiler.__complete_here(Compiler compiler, Symbol role, List keywords) {
  if (!compiler.at_completion()) return;
  List rows = compiler.sym.visible_symbols();
  raise %(
    replcomp (kind $role) (rows $rows) (keywords $keywords)
  );
}

/** Returns the first non-trivia token at or after `token`. */
Token Compiler.skip_trivia_from(Compiler compiler, Token token) =>
  _skip_forward(token);

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

/** Returns the non-trivia token type `steps` from parser position.

    Zero reads the current token; positive and negative steps count forward
    and backward through non-trivia tokens. The parser cursor is unchanged.
*/
Symbol Compiler.peek(Compiler compiler, int steps) {
  Token token = compiler.token;
  if (!steps && compiler.at_completion()) {
    List rows = compiler.sym.visible_symbols();
    raise %(replcomp (kind <names>) (rows $rows) (keywords ()));
  }
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
List Compiler.anchor_origin(Compiler compiler, List node, Token token) {
  if (!node) return node;
  if (compiler.macro_holes && !compiler.parsing_source_syntax())
    return %(at m-origin $node);
  int occurrence = compiler.record_origin(token);
  if (!occurrence) return node;
  return %(at $occurrence $node);
}

static int _shallow_parse_compile_time_definition(Compiler c, int keyword) {
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

/* Lexical privacy also marks a name in Sym.statics, so a static function is
   marked again as `(function name)`. File collection reads that key to keep
   the function out of what a private region publishes. */
static List _shallow_parse_declaration(Compiler compiler) {
  List declaration = compiler.parse_declaration_row();
  compiler.record_declaration_visibility(declaration);
  match (declaration)
    case %(declare ?type (bindings (bind ?binding ((fnmod *) *)))):
      if (type.type().is_static())
        compiler.sym.mark_static(
          %(function ${binding_identity_spelling(binding)}));
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
void Compiler._skip_shallow_expression(Compiler c, int stop_at_comma) {
  for (Symbol type = c.peek(0);
       type != <eof> && type != <;> && (!stop_at_comma || type != <,>);
       type = c.peek(0)) {
    if (type.group_step() > 0) c.token = c.token.after_group();
    else c.next();
  }
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
static void _report_script_statement(Compiler c) {
  c.report_error(
    <parse>, "a script that defines main cannot have top-level statements",
    c.token,
    %("move the statement into main, or remove main so the statements run"));
}

static void _shallow_finish_declaration(Compiler c) {
  /* Collection records the runtime function a `meta` marker precedes; the
     compile-time form is installed by the full parse. */
  Token meta = NULL;
  if (c.meta_form_is_declaration()) {
    meta = c.token;
    c.next();
  }
  List declaration = _shallow_parse_declaration(c);
  if (c.peek(0) == <"{"> || c.peek(0) == <"%{"> ||
      c._at_function_arrow()) {
    match (declaration)
      case %(declare ?type (bindings (bind ?binding ?))):
        _shallow_record_function_definition(c, type, binding);
    if (c._at_function_arrow()) {
      c.next();
      c.next();
      c._skip_shallow_expression(0);
      c.expect(<;>);
    }
    else _shallow_block(c);
  }
  else if (c.peek(0) == <;>) {
    if (meta) c.record_native_meta_effect(declaration, meta);
    c.next();
  }
  else c.next();
}

static String _declaration_path(String path, int thaw) {
  if (!path || path.startswith("<")) return path;
  return thaw ? home_absolute_path(path) : home_portable_path(path);
}

static List _declaration_location(Compiler compiler, List location, int thaw) {
  Array rows = [];
  foreach (List row, location) {
    match (row)
      case %(file ?path):
        row = %(file ${_declaration_path(path, thaw)});
    rows.push(row);
  }
  return rows.list_free();
}

static List _declaration_macro(Compiler compiler, List rows, int thaw) {
  Array result = [];
  foreach (List row, rows) {
    match (row) {
      case %(file ?path):
        row = %(file ${_declaration_path(path, thaw)});
      case %(origin ?location):
        row = %(origin ${_declaration_location(compiler, location, thaw)});
      default:
        row = thaw ? compiler.thaw_declaration_syntax(row)
                   : compiler.freeze_declaration_syntax(row);
    }
    result.push(row);
  }
  return %(macrodef @{result.list_free()});
}

/** Retains declaration syntax across source segments and cached interfaces.
    Tokens and origin indices become portable source data; marker-shaped user
    Lists are escaped so thawing preserves their values.
*/
Var Compiler.freeze_declaration_syntax(Compiler c, Var syntax) {
  if (syntax is void) return %(declaration-void);
  if (syntax is <symbol> && !syntax.symbol())
    return %(declaration-empty-symbol);
  if (syntax.is_atom() && !Atom.bare_spelling(syntax.str()))
    return %(declaration-atom ${syntax.str()});
  if (syntax is <token>) {
    Token token = syntax;
    return %(declaration-token ${token.type.str()} ${token.text}
              ${token.line} ${token.col} ${token.len} ${token.pos});
  }
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  match (syntax) {
    case %(macrodef *rows): return _declaration_macro(c, rows, 0);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source ${_declaration_path(path, 0)} $begin $end)
        ${c.freeze_declaration_syntax(node)});
    case %(at ?(int origin) ?node): {
      List location = c.origin_location(origin);
      if (!location)
        return %(at m-origin ${c.freeze_declaration_syntax(node)});
      return %(declaration-origin ${_declaration_location(c, location, 0)}
                ${c.freeze_declaration_syntax(node)});
    }
  }
  Array rows = [];
  foreach (Var row, syntax.list()) rows.push(c.freeze_declaration_syntax(row));
  match (syntax)
    case %((!or declaration-void declaration-empty-symbol declaration-atom
                declaration-token declaration-origin declaration-list) *):
      return %(declaration-list @{rows.list_free()});
  return rows.list_free();
}

/** Restores a retained declaration recipe in the current parsing lifetime. */
Var Compiler.thaw_declaration_syntax(Compiler c, Var syntax) {
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  match (syntax) {
    case %(declaration-list *rows): {
      Array values = [];
      foreach (Var row, rows) values.push(c.thaw_declaration_syntax(row));
      return values.list_free();
    }
    case %(macrodef *rows): return _declaration_macro(c, rows, 1);
    case %(src (source ?path ?begin ?end) ?node):
      return %(src (source ${_declaration_path(path, 1)} $begin $end)
        ${c.thaw_declaration_syntax(node)});
    case %(declaration-void): return void;
    case %(declaration-empty-symbol): return (Symbol) 0;
    case %(declaration-atom ?spelling): return Atom.intern(spelling);
    case %(declaration-token ?type ?text ?line ?column ?length ?position): {
      Token token = Scope.calloc(1, sizeof(struct Token));
      *token = (struct Token) {
        .text = text, .type = Symbol.new(type.string()), .line = line,
        .col = column, .len = length, .pos = position};
      return token;
    }
    case %(declaration-origin ?location ?node): {
      List source = location;
      c.origins.push(%(source ${source.assoc(<file>)}
        ${source.assoc(<line>)} ${source.assoc(<column>)}
        ${source.assoc(<length>)} ${source.assoc(<position>)}));
      return %(at ${c.origins.len()} ${c.thaw_declaration_syntax(node)});
    }
  }
  Array rows = [];
  foreach (Var row, syntax.list()) rows.push(c.thaw_declaration_syntax(row));
  return rows.list_free();
}

static List _declaration_source_key(Compiler compiler, Token token) {
  String path = home_portable_path(Path.absolute(compiler.filename));
  return %("source-node" (declaration $path ${token.pos}));
}

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

/** Runs pending effects for declaration production or CPP macro evaluation. */
void Compiler.run_declaration_effects(Compiler c) {
  List effects = c.declaration_effects.reverse();
  c.declaration_effects = NULL;
  foreach (List effect, effects) {
    (List key, int end, String form, Var site, String context) = effect;
    String filename = c.filename;
    match (key)
      case %("source-node" (declaration ?path ?)):
        c.filename = _declaration_path(path, 1);
    c.import_stack.push(context);
    defer {
      c.import_stack.take_last();
      c.filename = filename;
    }
    Token token = c.thaw_declaration_syntax(site);
    c.evaluate_declaration_effect(form, token);
    if (c.collect_protocols)
      c.sym.set(key, %(declaration-source $end (declaration-bundle (rows))));
  }
}

/* The owning source records one declaration production, including its exact
   token span. Full parsing consumes that production instead of invoking its
   compile-time producer again. Ordinary Unit macros retain their old path. */
static int _retain_declaration_bundle(
  Compiler compiler, List syntax, Token first, Token after) {
  match (syntax) {
    case %(seq ?only):
      return _retain_declaration_bundle(compiler, only, first, after);
    case %(declaration-bundle (rows *)): {
      List frozen = compiler.freeze_declaration_syntax(syntax);
      compiler.sym.set(_declaration_source_key(compiler, first),
        %(declaration-source ${after.pos} $frozen));
      return 1;
    }
  }
  return 0;
}

static List _bind_declaration_default(Compiler compiler, List syntax) {
  if (compiler.source_private)
    match (syntax)
      case %(function ?type ?declarator ?body):
        if (!type.type().is_static())
          syntax = %(function (static @type) $declarator $body);
  return compiler.bind_syntax(syntax, AST_UNIT, NULL);
}

static void _produce_declaration_rows(
  Compiler compiler, List rows, Array selected) {
  foreach (List row, rows) {
    match (row) {
      case %(declaration-pending ?callback ?arguments
               ?construction ?privacy): {
        $let(compiler.macro_stack,
             compiler.thaw_declaration_syntax(construction))
        $let(compiler.source_private, privacy) {
          List generated = compiler.bind_syntax(
            compiler.evaluate_declaration_recipe(callback, arguments),
            AST_UNIT, NULL);
          List additions = %($generated);
          match (generated) {
            case %(seq *children): additions = children;
            case %(declaration-bundle (rows *children)): additions = children;
          }
          _produce_declaration_rows(compiler, additions, selected);
        }
        continue;
      }
    }
    selected.push(row);
  }
}

static List _select_declaration_rows(Compiler compiler, List rows) {
  Array selected = [];
  foreach (List row, rows) {
    match (row) {
      case %(declaration-default ?function ?construction ?privacy): {
        $let(compiler.macro_stack,
             compiler.thaw_declaration_syntax(construction))
        $let(compiler.source_private, privacy) {
          List syntax = function;
          match (syntax)
            case %(function ?return_type (bind ?name ?modifiers) ?body): {
              name = compiler.evaluate_macro_slot(name);
              String spelling = binding_identity_spelling(name);
              match (name) {
                case %(?(String literal)): spelling = literal;
                case %("x2c.ident" ?(String literal)): spelling = literal;
              }
              if (spelling && compiler.sym.get(%($spelling))) continue;
              syntax = %(function $return_type (bind $name $modifiers) $body);
            }
          selected.push(_bind_declaration_default(compiler, syntax));
        }
        continue;
      }
    }
    selected.push(row);
  }
  return selected.list_free();
}

static List _declaration_forward(
  Compiler compiler, Type child, Type parent, String member,
  List fallback, Map pending) {
  String name = %"${child.car()}_$member";
  if (compiler.sym.get(%($name))) return %(seq);
  List method = compiler.resolve_postfix_member(parent, %($member), <.>, 1);
  if (!method) {
    if (parent in pending) return NULL;
    return fallback ? _bind_declaration_default(compiler, fallback.car())
                    : NULL;
  }
  List binding = NULL, Type signature = NULL;
  match (method)
    case %(method ?target ?type): {
      binding = target;
      signature = type;
    }
  if (!signature) return NULL;
  List types = NULL;
  match (signature) case %((func ?parameters) *): types = parameters;
  Array parameters = [], arguments = [];
  int index = 0;
  foreach (Var type, types) {
    if (type == <...>)
      compiler.report_error(<type>,
        %"'$name' requires an explicit variadic constructor",
        compiler.token, NULL);
    if (type == %(void)) continue;
    String argument = %"argument$index";
    index++;
    parameters.push(%(param $type (bind ($argument) ())));
    arguments.push(%(expr $type (ident ($argument))));
  }
  List call = %(expr ()
    (call (expr $signature (ident $binding)) (args @{arguments.list_free()})));
  List body = %(block (return () (expr () (cast $child $call))));
  List function = %(function $child
    (bind ($name) ((fnmod (params @{parameters.list_free()})))) $body);
  return _bind_declaration_default(compiler, function);
}

static List _select_declaration_forwards(
  Compiler compiler, List rows, Map pending, int *remaining) {
  Array selected = [];
  foreach (List row, rows) {
    match (row)
      case %(declaration-forward ?child ?parent ?member ?fallback ?privacy): {
        $let(compiler.source_private, privacy) {
          List bound = _declaration_forward(
            compiler, child, parent, member, fallback, pending);
          if (!bound) {
            (*remaining)++;
            selected.push(row);
          }
          else {
            pending.del(child);
            if (bound.car() != <seq>) selected.push(bound);
          }
        }
        continue;
      }
    selected.push(row);
  }
  return selected.list_free();
}

/** Selects the owning file's declaration defaults after all its segments.
    The selected signatures join ordinary declarations before protocol and
    body binding; discarded candidates never bind their bodies. Returns added
    signatures for the caller to retain in the header-cache lifetime.
*/
Map Compiler.select_declaration_defaults(
  Compiler compiler, String path, Map symbols, Array parts,
  Map definitions) {
  int present = 0;
  foreach (Var part, parts) {
    if (part is not <map>) continue;
    foreach (Var value, part.map())
      match (value) case %(declaration-source *): present = 1;
  }
  if (!present) return NULL;
  Compiler shadow = Compiler.new_shared(compiler);
  defer compiler.close_child(shadow);
  shadow.filename = path;
  shadow.macro_lisp = compiler.macro_lisp;
  shadow.borrowed_lisp = shadow.macro_lisp != NULL;
  shadow.sym._reset_overlay(symbols, {});
  shadow.rebuild_protocols(symbols);
  shadow.conforms = {};
  shadow.shallow = 1;
  shadow.declaration_projection = 1;
  Array sources = [];
  Map pending = {};
  foreach (Var part, parts) {
    if (part is not <map>) continue;
    Map declarations = part;
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
        case %(declaration-source ?end
                 (declaration-bundle (rows *rows))): {
          rows = shadow.thaw_declaration_syntax(rows);
          Array produced = [];
          _produce_declaration_rows(shadow, rows, produced);
          sources.push(%($declarations $key $end ${produced.list_free()}));
        }
    }
  }
  for (size_t index = 0; index < sources.len(); index++) {
    (Map declarations, Var key, Var end, List rows) = sources[index];
    List selected = _select_declaration_rows(shadow, rows);
    foreach (List row, selected)
      match (row)
        case %(declaration-forward ?child *): pending[child] = 1;
    sources[index] = %($declarations $key $end $selected);
  }
  int remaining = pending.len();
  while (remaining) {
    int previous = remaining;
    remaining = 0;
    for (size_t index = 0; index < sources.len(); index++) {
      (Map declarations, Var key, Var end, List rows) = sources[index];
      rows = _select_declaration_forwards(shadow, rows, pending, &remaining);
      sources[index] = %($declarations $key $end $rows);
    }
    if (remaining && remaining == previous)
      shadow.report_error(<type>,
        "a forwarded class constructor has no completed parent constructor",
        shadow.token, NULL);
  }
  foreach (List source, sources) {
    (Map declarations, Var key, Var end, List rows) = source;
    declarations[key] = shadow.freeze_declaration_syntax(
      %(declaration-source $end (declaration-bundle (rows @rows))));
    symbols[key] = declarations[key];
  }
  Map additions = shadow.sym.current_symbols();
  symbols.merge(additions);
  compiler.merge_source_declarations(symbols, additions);
  compiler.fn_defs.merge(shadow.fn_defs);
  definitions.merge(shadow.fn_defs);
  return additions;
}

static List _replay_declaration_bundle(Compiler compiler) {
  List source = compiler.sym.get(_declaration_source_key(
    compiler, compiler.token));
  match (source)
    case %(declaration-source ?(int end) ?syntax): {
      List thawed = compiler.thaw_declaration_syntax(syntax);
      List result = compiler.bind_syntax(thawed, AST_UNIT, NULL);
      while (compiler.peek(0) != <eof> && compiler.token.pos < end)
        compiler.next();
      return result;
    }
  return NULL;
}

/* Expand an imported file-scope unit macro so later invocations can use its
   private helpers and other units can see its public declarations. */
static void _shallow_parse_unit_macro(Compiler compiler) {
  with compiler.names {
    Map saved_counters = _.counters;
    _.counters = _.counters.copy();
    with compiler {
      SymTxn transaction = _.begin_semantic_transaction();
      Token first = _.token;
      List syntax = _.parse_top_level();
      int retained = _retain_declaration_bundle(_, syntax, first, _.token);
      transaction.commit();
      if (retained) return;
    }
    /* The full parse expands this unit again. Keep the declarations needed
       by later shallow invocations, but do not count its generated names
       twice. */
    _.counters = saved_counters;
  }
}

static void _shallow_parse_loop(Compiler c) {
  c.rebuild_protocols(NULL);
  c.conforms = {};
  c.shallow = 1;
  c.braces.clear();
  while (c.peek(0) != <eof>) {
    c.update_source_visibility(c.leading_preproc());
    if (c.skip_linkage_brace()) continue;
    Token start = c.token;
    if (c.script && !c.script.defines_main && c.script_statement_starts()) {
      c.skip_script_statement();
      continue;
    }
    if (c.script && c.script.defines_main && c.script_statement_executes())
      _report_script_statement(c);
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
    if (c.protocol_form_starts()) {
      c.parse_protocol_declaration();
      _debug_tokens(c, start, c.token);
      continue;
    }
    if (c.keyword_form_is_definition()) {
      _shallow_parse_compile_time_definition(c, 1);
      _debug_tokens(c, start, c.token);
      continue;
    }
    if (c.macro_form_is_definition()) {
      _shallow_parse_compile_time_definition(c, 0);
      _debug_tokens(c, start, c.token);
      continue;
    }
    if (!c.collect_protocols && c.skip_named_type_declaration()) {
      _debug_tokens(c, start, c.token);
      continue;
    }
    if (c.macro_starts_target_at(AST_UNIT)) {
      if (c.collect_protocols && c.macro_invocation_needs_shallow_expansion())
        _shallow_parse_unit_macro(c);
      else {
        c.skip_macro_invocation();
        if (!c.test(<;>)) {
          while (c.macro_starts_target_at(AST_UNIT)) {
            c.skip_macro_invocation();
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
  /* Definitions after the last declaration, as before an include, still
     define macros for the segments that follow. */
  foreach (List directive, c.leading_preproc())
    _note_object_macro(c, directive.cadr());
  _check_unmatched_braces(c);
  c.shallow = 0;
}

/** Collects file-scope declarations into `globals` without parsing bodies. */
void Compiler.shallow_parse(Compiler c, Map globals) {
  c.macros = {};
  c.kw_aliases = {};
  c.kw_seen = {};
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
  int initialize_macros = (void *) c.macros == NULL || !c.macros.len();
  if (initialize_macros) {
    c.macros = {};
    if ((void *) c.kw_aliases == NULL) c.kw_aliases = {};
    if ((void *) c.kw_seen == NULL) c.kw_seen = {};
    c.imports = {};
    c.import_stack.clear();
  }
  c.sym._reset_overlay(base, overlay);
  c.install_builtin_macros();
  _shallow_parse_loop(c);
}

/** Returns source-ordered preprocessor nodes in the preceding trivia.

    Spaces and comments remain trivia rather than becoming AST nodes.
*/
List Compiler.leading_preproc(Compiler compiler) {
  List noncode = %();
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
    if (type.is_storage_class() || type.is_inline() ||
        type.is_type_qualifier() || type.is_builtin_type())
      words.push(type);
    else if (type == <lit-char*>);   // the linkage name in `extern "C"`
    else if (type != <ident>) return 1;
    else if (word == "__attribute__" || word == "__declspec" ||
             (c.object_macros.try_get(word, &definition) &&
              definition.equal(<annotation>))) {
      if (next.type != <(>) return 1;
      next = next.after_group();
    }
    else if (param && word == param && !wrapped) wrapped = 1;
    else if (!c.object_macros.try_get(word, &definition) ||
             definition is not <list>)
      return 1;
    else foreach (Var item, definition) words.push(item);
    token = next;
  }
  return wrapped ? <wrapper> : words.list_free();
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

/* Records the name of each `#define` so a bare atom spelled the same way
   inside a literal can be flagged and a declaration prefix can be read.
   The directive after `#define` is scanned as x2c tokens: an object-like
   body is classified by `_macro_prefix`; a function-like macro whose body
   is empty or an attribute is `<annotation>`, one that wraps its parameter
   is `<wrapper>`, and any other function-like macro is skipped. An `#undef`
   drops the name, so later source reads it as an ordinary identifier. */
static void _note_object_macro(Compiler c, String content) {
  int undefined;
  Token token = _macro_directive(content, &undefined);
  if (!token) return;
  String name = token.text;
  if (undefined) {
    c.object_macros.del(name);
    return;
  }
  Token body = token + 1;
  if (body.type == <(>) {
    // A parameter list touching the name makes the macro function-like.
    Token after = body.after_group(), String param = NULL;
    Token first = _skip_forward(body + 1);
    if (first.type == <ident> && _skip_forward(first + 1).type == <)>)
      param = first.text;
    Var kind = _macro_prefix(c, after, param);
    if (kind.equal(%())) c.object_macros[name] = <annotation>;
    else if (kind.equal(<wrapper>)) c.object_macros[name] = <wrapper>;
    return;
  }
  Var definition = _macro_prefix(c, _skip_forward(token + 1), NULL), existing;
  /* A name another arm defines to anything but a string literal is no string
     literal: `Var v = SEP;` must not make a String of the other arm's
     number. */
  if (!c.object_macros.try_get(name, &existing) ||
      _prefix_rank(definition) > _prefix_rank(existing) ||
      (existing.equal(<string>) && !definition.equal(<string>)))
    c.object_macros[name] = definition;
}

/** Applies public and private pragma directives to source visibility state
    and records each object-like `#define` name, less those `#undef` drops,
    for the literal warning.

    A negative visibility state disables pragma tracking for this token
    stream; macro names are recorded regardless.
*/
void Compiler.update_source_visibility(Compiler c, List directives) {
  foreach (List directive, directives) {
    String content = directive.cadr();
    _note_object_macro(c, content);
  }
  if (c.source_private < 0) return;
  foreach (List directive, directives) {
    String content = directive.cadr();
    if (content.contains("pragma private")) c.source_private = 1;
    else if (content.contains("pragma public")) c.source_private = 0;
  }
}

// Prepend source-ordered directives to an AST accumulated in reverse order.
static void _append_preproc(Compiler compiler, Array ast) {
  List directives = compiler.leading_preproc();
  compiler.update_source_visibility(directives);
  foreach (Var directive, directives) ast.push(directive);
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

/* Records every binding `node` names, so a `meta` definition is emitted only
   where the unit reaches it. A definition's own binder is a `bind`, not an
   `ident`, so a function does not name itself here. */
static void _collect_binding_references(Var node, Map referenced) {
  if (node is not <list>) return;
  List syntax = node;
  match (syntax) case %(ident (binding ?identity ?)): {
    referenced[identity] = 1;
    return;
  }
  foreach (Var child, syntax) _collect_binding_references(child, referenced);
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
  foreach (List node, nodes) _collect_binding_references(node, referenced);
  /* A `meta` declaration uses only ones declared before it, so one pass
     from the last declaration back reaches every one an emitted one
     needs. */
  for (size_t i = c.meta_defs.len(); i; i--) {
    List definition = c.meta_defs[i - 1];
    Var identity = _meta_identity(definition);
    if (identity in referenced) {
      reached[identity] = 1;
      _collect_binding_references(definition, referenced);
    }
  }
  foreach (List definition, c.meta_defs)
    if (_meta_identity(definition) in reached &&
        !c.meta_is_comptime_only(definition)) {
      _record_top_level_function_state(c, definition);
      nodes.push(definition);
    }
}

/** Parses and types the positioned source against `globs`.

    The result is a source-ordered top-level AST. This resets per-parse
    origins, macro state, and protocol resolution.
    `generated_symbols` publishes external adapter signatures before parsing.
*/
List Compiler.full_parse(Compiler c, Map globs, int generated_symbols) {
  Array nodes = [];
  c.origins.clear();
  c.meta_defs.clear();
  /* Binding ids are reissued by the reset below, so a fold recorded against
     the previous pass's numbering would name a different binding. */
  c.meta_folds = {};
  c.meta_impure = {};
  c.meta_comptime = {};
  c.meta_regions = {};
  c.meta_values = {};
  c.meta_layouts = {};
  c.native_meta = {};
  c.inherit_shared_meta();
  c.fixed = {};
  c.init_tokens = {};
  c.static_init_deps = {};
  c.origin = 0;
  c.braces.clear();
  c.arms = NULL;
  c.sym.reset(globs);
  c.rebuild_protocols(globs);
  c.macros = {};
  c.kw_aliases = {};
  c.kw_seen = {};
  c.install_builtin_macros();
  if (!c.declaration_produced) c.imports = {};
  c.import_stack.clear();
  c.macro_count = 0;
  c.macro_stack = NULL;
  c.source_private = 0;
  c.resolve_protocols();
  if (generated_symbols) c.install_generated_protocol_symbols();
  c.install_native_meta_effects(globs);
  Map saved_holes = c.macro_holes;
  defer c.macro_holes = saved_holes;
  int saved_runtime_literals = c.runtime_literals;
  defer c.runtime_literals = saved_runtime_literals;
  if (c.source_syntax) {
    c.runtime_literals = 1;
    c.macro_holes = {};
    c.macro_holes[%(locals)] = (Map) {};
    c.macro_holes[%(source-ast)] = 1;
  }
  Token conflict = NULL;
  $let(c.recovery_depth, c.recovery_depth + 1) {
    _append_preproc(c, nodes);
    Array statements = [];
    int hoisting = c.script && !c.script.defines_main;
    int gap = 0, runs = 0, first = 0;
    loop {
      while (c.peek(0) != <eof>) {
        Token start = c.token;
        int braces = c.braces.len();
        try {
          Token tokens = c.tokenizer.tokens;
          if (hoisting)
            _push_script_conditionals(c, statements, gap, start - tokens);
          if (hoisting && c.script_statement_starts()) {
            c.skip_script_statement();
            int begin = start - tokens;
            int end = _skip_backward(c.token - 1, tokens) + 1 - tokens;
            statements.push(begin);
            statements.push(end);
            if (!runs++) first = begin;
          }
          else {
            if (c.script && c.script.defines_main &&
                c.script_statement_executes())
              _report_script_statement(c);
            Ast node = NULL;
            if (c.source_syntax) {
              // Establish generated grammar, then retain the source invocation.
              $let(c.macro_holes, NULL)
              $let(c.runtime_literals, saved_runtime_literals)
              $let(c.token, c.token) {
                if (!_replay_declaration_bundle(c)) {
                  if (c.peek(0) == <"$(">)
                    c.parse_macro_lisp_top_level();
                  else if (c.macro_starts_target_at(AST_UNIT) &&
                           c.macro_targets_unit())
                    (void) c.parse_top_level();
                }
              }
            }
            else node = _replay_declaration_bundle(c);
            if (!node) node = c.parse_top_level();
            if (node && node.car() == <seq>) {
              foreach (List item, node.cdr()) {
                _record_top_level_function_state(c, item);
                nodes.push(item);
              }
            }
            else if (node) {
              _record_top_level_function_state(c, node);
              nodes.push(node);
            }
          }
          gap = _skip_backward(c.token - 1, tokens) + 1 - tokens;
          _append_preproc(c, nodes);
          _debug_tokens(c, start, c.token);
        }
        catch %(malformed (category ?category) *): {
          (void) category;
          if (c.diagnostics.reached_limit()) break;
          _sync_top_level(c, start, braces);
          Token tokens = c.tokenizer.tokens;
          gap = _skip_backward(c.token - 1, tokens) + 1 - tokens;
          _append_preproc(c, nodes);
          if (c.peek(0) == <eof>) break;
          continue;
        }
      }
      if (!runs) break;
      Token tokens = c.tokenizer.tokens;
      // A macro can still define `main` where the token scan saw none.
      if (c.fn_defs.contains("main")) {
        conflict = tokens + first;
        break;
      }
      _push_script_conditionals(c, statements, gap, c.token - tokens);
      _append_script_main(c, statements);
      hoisting = runs = 0;
    }
  }
  if (conflict) {
    c.token = conflict;
    _report_script_statement(c);
  }
  _append_meta_definitions(c, nodes);
  List ast = nodes.list_free();
  if (c.script && !c.script.defines_main && !c.error_count())
    _check_script_locals(c, ast);
  _check_unmatched_braces(c);
  if (!c.source_syntax && !c.error_count())
    _validate_static_object_initializers(c);
  return ast;
}

/* A file-scope conditional directive also governs the statements it
   surrounds, so a copy of each joins the statement runs in source order and
   the script body keeps the file's conditional structure. */
static void _push_script_conditionals(
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

/* A script's functions cannot see the variables declared among its
   statements, which are locals of `x2c_script`. C would report such a name
   as undeclared; this names the cause and the `static` spelling that
   shares it. */
static void _check_script_locals(Compiler c, List ast) {
  Map locals = {};
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? "x2c_script") ?) (block *items)):
      foreach (List item, items) match (item)
        case %(at ? (declare ? (bindings *bindings))):
          foreach (List binding, bindings) match (binding)
            case %(!or (bind (binding ? ?(String name)) ?)
                       (op = (bind (binding ? ?(String name)) ?) ?)):
              locals[name] = 1;
  if (!locals.len()) return;
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? ?(String function)) ?)
           (block *items)): {
      if (function == "x2c_script" || function == "main") continue;
      foreach (List item, items) match (item) case %(at ?origin ?statement):
        foreach (Var name, locals.keys()) {
          Var found;
          List bindings;
          if (!statement.list().try_search(
                %(expr () (ident (binding ? $name))), &found, &bindings))
            continue;
          c.origin = origin;
          c.report_error(
            <type>,
            %"'$name' is declared among the script's statements",
            NULL,
            %("functions cannot see those locals;"
              "declare it static to share it"));
        }
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
   Template tokens take the first statement's position with no length, so a
   diagnostic about them names the script without reading past its text.
   `statements` holds each run's first and past-the-end token index. */
static void _append_script_main(Compiler c, Array statements) {
  Token tokens = c.tokenizer.tokens, eof = c.token;
  long kept = _skip_backward(eof - 1, tokens) + 1 - tokens;
  Token first = tokens + statements[0].integer();
  Bytes stream = Bytes.new(sizeof(struct Token));
  stream = stream.append(tokens, kept);
  Tokenizer template = Tokenizer.new((char *) script_main);
  template.scan();
  for (Token token = template.tokens; token.type != <eof>; token++) {
    if (token.text == "x2c_script_statements") {
      for (int i = 0; i < statements.len(); i += 2) {
        long start = statements[i];
        long end = statements[i + 1];
        stream = stream.append(tokens + start, end - start);
      }
      continue;
    }
    struct Token placed = *token;
    placed.line = first.line;
    placed.col = first.col;
    placed.pos = first.pos;
    placed.len = 0;
    stream = stream.append(&placed, 1);
  }
  stream = stream.append(eof, 1);
  c.tokenizer.tokens = stream;
  c.token = _skip_forward((Token) stream + kept);
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
  if (value.is_integer()) {
    List literal = compiler.meta_value_expression(%("Var"), value, 0);
    return literal ? compiler.cache(%(var $literal)) : NULL;
  }
  String spelling = value.symbol();
  List literal = %(
    expr ("Symbol") (literal ("Symbol") $spelling $value)
  );
  return compiler.cache(%(var $literal));
}

static List _cache_literal_list(Compiler compiler, List values) {
  Array heads = $auto([]);
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

    `values` may contain nested `List`s, `String`s, integer `Var`s, and
    `Symbol`s.
*/
List Compiler.cache_literal_list(Compiler compiler, List values) {
  List cached = _cache_literal_list(compiler, values);
  return %(expr ("List") (expr ("List") $cached));
}

/* Recover the compile-time value graph behind a Match pattern.  Dynamic
   expressions are represented by a private marker so binder analysis can
   distinguish a computed operator head from ordinary literal data. */
static String _match_pattern_converter_name(Var node) {
  if (node is <string>) return node;
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
  if (converter == "List_var" || converter == "Symbol_var")
    match (third) case %(args ?argument):
      return c.match_pattern_value(argument);
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
  _match_pattern_value_is_static(compiler.match_pattern_value(pattern));

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

/** Returns the head of a flat Symbol-and-captures pattern, or zero.

    Each element after the head is a unique named `?` binder or a typed
    capture of one. When `tags` is non-null, stores one entry per binder
    in order: the capture's tag Symbol, or integer zero when untyped.
*/
Symbol Compiler.match_pattern_flat_head(
  Compiler compiler, List pattern, List binders, List *tags) {
  Symbol head = compiler.match_pattern_head_symbol(pattern);
  if (!head) return 0;
  List elements = compiler.match_pattern_value(pattern).list().cdr();
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
  if (tags) *tags = typed.list_free();
  else typed.free();
  return head;
}

/** Returns definite binders from a typed `Match` pattern AST.

    When `possible` is non-null, stores every binder appearing on any path.
*/
List Compiler.match_pattern_binders(Compiler c, List pattern, List *possible) {
  Var value = c.match_pattern_value(pattern);
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

/** Appends a statement to file initialization order under `phase`, which is
    `<protocol>` for protocol setup, or `<early>`, `<mid>`, or `<late>` for
    the file initializer's three stages.
*/
void Compiler.add_init(Compiler compiler, Symbol phase, List stmt) {
  compiler.inits.push(%($phase $stmt));
}

/** Returns the statements queued for `phase`, in the order they were added. */
List Compiler.init_statements(Compiler compiler, Symbol phase) {
  Array selected = [];
  foreach (List entry, compiler.inits)
    if (entry.car() == phase) selected.push(entry.cadr());
  return selected.list_free();
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
  int local_macro_names;
  SymScope scope;
  Map statics, binding_facts;
  Map meta_layouts;
  Map source_definitions;
  int source_occurrences;
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
  transaction.scope = *scope;
  transaction.counters = c.names.counters;
  transaction.statics = c.sym.statics;
  transaction.binding_facts = c.semantic_binding_facts();
  transaction.meta_layouts = c.meta_layouts;
  transaction.next_binding = c.names.next_binding;
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
  c.sym.binding_facts = c.semantic_binding_facts().copy();
  c.names.counters = c.names.counters.copy();
  c.meta_layouts = c.meta_layouts.copy();
  transaction.active = 1;
  return transaction;
}

/** Publishes an active semantic transaction and makes rollback a no-op. */
void SymTxn.commit(SymTxn s) {
  if (!s || !s.active) return;
  Compiler compiler = s.compiler;
  SymScope *scope = _semantic_scope(compiler.sym, s.scope_index);
  SymScope staged = *scope;
  /* Restore the original map identities before merging staged rows. Code
     holding a borrowed scope map must observe a committed expansion. */
  *scope = s.scope;
  scope.symbols.merge(staged.symbols);
  compiler.merge_source_declarations(scope.symbols, staged.symbols);
  scope.bindings.merge(staged.bindings);
  scope.enumerators.merge(staged.enumerators);
  if ((void *) staged.macros != NULL) {
    if ((void *) scope.macros == NULL) scope.macros = {};
    scope.macros.merge(staged.macros);
  }
  s.meta_layouts.merge(compiler.meta_layouts);
  compiler.meta_layouts = s.meta_layouts;
  s.active = 0;
}

/* Copy the staged state back without retaining its container. Deletions
   matter: a declaration can remove an earlier file-static designation. */
static void _replace_transaction_map(Map original, Map staged) {
  Array keys = $auto(original.keys());
  foreach (Var key, keys) if (!staged.contains(key)) original.del(key);
  original.merge(staged);
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
  _replace_transaction_map(s.statics, statics);
  _replace_transaction_map(s.binding_facts, facts);
  _replace_transaction_map(s.counters, counters);
}

/** Returns whether the transaction's active scope changed its macro map. */
int SymTxn.local_macros_changed(SymTxn s) {
  SymScope *scope = _semantic_scope(s.compiler.sym, s.scope_index);
  Map before = s.scope.macros, after = scope.macros;
  if ((void *) before == NULL || (void *) after == NULL)
    return (void *) before != (void *) after;
  return !before.equal(after);
}

/** Restores every semantic value captured by an active transaction. */
void SymTxn.rollback(SymTxn transaction) {
  if (!transaction || !transaction.active) return;
  Compiler compiler = transaction.compiler;
  with compiler {
    SymScope *scope = _semantic_scope(_.sym, transaction.scope_index);
    *scope = transaction.scope;
    _.sym.statics = transaction.statics;
    _.sym.binding_facts = transaction.binding_facts;
    _.meta_layouts = transaction.meta_layouts;
    _.names.next_binding = transaction.next_binding;
    _.sym.local_macro_names = transaction.local_macro_names;
    _.names.counters = transaction.counters;
    _.init_fn = transaction.initializer_name;
    _.fini_fn = transaction.shutdown_name;
    if (_.source_facts && _.source_primary) {
      _.source_occurrences.resize(transaction.source_occurrences);
      foreach (Var key, _.source_definitions.keys().list())
        _.source_definitions.del(key);
      _.source_definitions.merge(transaction.source_definitions);
    }
    transaction.active = 0;
  }
}

static void _semantic_reset(Sym sym, Map base, Map globals, int overlay) {
  sym.scopes.clear();
  sym.globals = (void *) globals != NULL ? globals : {};
  sym.statics = {};
  sym.base_scopes = overlay ? 2 : 1;
  sym.local_macro_names = 0;
  sym.binding_facts = {};
  if (overlay) {
    struct SymScope base_scope = {
      .symbols = (void *) base != NULL ? base : {},
      .bindings = {}, .enumerators = {}
    };
    sym.scopes.push(&base_scope);
  }
  struct SymScope scope = {
    .symbols = sym.globals,
    .bindings = {},
    .enumerators = {}
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
  Map seed = {};
  for (int i = 0; i < sym.base_scopes; i++)
    seed.merge(_semantic_scope(sym, i).symbols);
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

/** Returns the visible one-part source names and their semantic types.
    Inner scopes win. The result is a fresh List; types remain borrowed. */
List Sym.visible_symbols(Sym sym) {
  Map seen = {};
  Array rows = [];
  for (int i = (int) sym.scopes.len() - 1; i >= 0; i--) {
    SymScope *scope = _semantic_scope(sym, i);
    foreach (Var (key, value), scope.symbols)
      match (key)
        case %(?(String name)):
          if (!seen.contains(name)) {
            seen[name] = 1;
            rows.push(%($name $value));
          }
    if ((void *) scope.macros != NULL)
      foreach (Var (name, definition), scope.macros)
        if (name is <string> && !seen.contains(name)) {
          seen[name] = 1;
          Symbol kind = definition is <list>
                      ? definition.list().assoc(<kind>) : 0;
          rows.push(%($name ${kind == <type> ? <typemacro> : <macro>}));
        }
  }
  return rows.list_free();
}

/** Returns `key`'s binding in the current scope, or `NULL`. */
List Sym.current_binding(Sym sym, List key) {
  SymScope *scope = _semantic_scope(sym, -1);
  Var binding;
  return scope && scope.bindings.try_get(key, &binding)
       ? binding : NULL;
}

/** Returns the current scope's enum owner for `key`, or zero. */
Symbol Sym.enumerator_owner(Sym sym, List key) {
  SymScope *scope = _semantic_scope(sym, -1);
  Var owner;
  return scope && scope.enumerators.try_get(key, &owner)
       ? owner : 0;
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
  if ((void *) scope.macros == NULL) scope.macros = {};
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

/** Returns whether declarations currently bind at file scope. */
int Sym.at_file_scope(Sym sym) => (int) sym.scopes.len() <= sym.base_scopes;

/** Returns the innermost visible local macro named `name`, or `NULL`. */
List Sym.lookup_macro(Sym sym, Atom name) {
  Var definition;
  for (int i = (int) sym.scopes.len() - 1; i >= sym.base_scopes; i--) {
    SymScope *scope = _semantic_scope(sym, i);
    if ((void *) scope.macros != NULL &&
        scope.macros.try_get(name, &definition))
      return definition;
  }
  return NULL;
}

static int _retained_aggregate_member(List key) =>
  !!key.match(%((!or struct union)
    (!or (binding ? ?) (gensym ? ?)) ? *));

/** Sets a semantic type for `key` in the required active scope. */
void Sym.set(Sym s, List key, List type) {
  SymScope *current = _semantic_scope(s, -1);
  Map scope = current.symbols;
  if (log_should_log(<debug>, <symtab>))
    log_debug(<symtab>, %( (func "Sym.set") (key $key) (val $type) ));
  scope[key] = type;
  if (_retained_aggregate_member(key)) s.binding_facts[%(aggfact $key)] = type;
}

static List _semantic_new_binding(Sym sym, List key) {
  int identity = ++sym.compiler.names.next_binding;
  Var name = key.last();
  List binding = binding_identity_new(identity, name);
  sym.binding_facts[%(known $identity)] = name;
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
    case %((func ((?(String named)))) "Var"): {
      String owner = named, converter = %"${owner}_var";
      match (key)
        case %(?(String spelling)):
          return spelling == converter ? owner : NULL;
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

/** Defines `key` in the unit's writable base scope.

    The definition survives the expression scope that first resolved it. Its
    binding is issued at the first reference, as for a row an included file
    contributes, so the unit numbers its bindings the same whether it defined
    the row here or replayed it from an interface.
*/
void Sym.define_global(Sym sym, List key, List type) {
  SymScope *scope = _semantic_scope(sym, sym.base_scopes - 1);
  scope.symbols[key] = type;
  _seed_declared_var_tag(key, type);
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
  String spelling = key.car();
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

/** Resolves a global name or creates its forward binding in the base scope.
    Local declarations cannot capture a retained macro's global reference.
*/
List Sym.reference_global(Sym sym, List key) {
  List binding = sym.resolve_global(key, NULL);
  return binding ? binding : _semantic_scope_binding(
    sym, _semantic_scope(sym, sym.base_scopes - 1), key);
}

/** Reports whether `binding` belongs to a scope inside the base scopes. */
int Sym.binding_is_local(Sym sym, List binding) =>
  sym.binding_is_local_before(binding, sym.scopes.len());

/** Reports whether `binding` belongs to a local scope below `scope_count`.

    Counts beyond the current scope depth are clamped to that depth.
*/
int Sym.binding_is_local_before(Sym sym, List binding, int scope_count) {
  if (scope_count > (int) sym.scopes.len()) scope_count = sym.scopes.len();
  for (int i = scope_count - 1; i >= sym.base_scopes; i--)
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
  if (s == "_init_guard_") return 1;
  if (s == "_file_init_") return 1;
  if (s.len() < 2 || s[0] != '_') return 0;
  for (int i = 1; i < s.len(); i++) if (s[i] < '0' || s[i] > '9') return 0;
  return 1;
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

/** Registers one local package alias.

    Shallow collection and full parsing both see an import, so repeating the
    same package and alias is a no-op. Another binding of the local spelling
    is a parse error.
*/
void Compiler.register_package_alias(
  Compiler compiler, String name, String alias, Token token) {
  Var bound = compiler.package_aliases[alias];
  if (bound is not void && bound == name) return;
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
  List packages = %();
  foreach (Var (key, root), c.package_roots) {
    String package = key;
    if (c.sym.get_exact(%("${package}__$name")))
      packages = cons(package, packages);
  }
  return packages.sort();
}

/** Returns an unambiguous imported spelling for `name`, or `NULL`. */
String Compiler.imported_spelling(Compiler compiler, String name) {
  List packages = compiler.imported_providers(name);
  if (!packages || packages.cdr()) return NULL;
  return %"${packages.car()}__$name";
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
    return %(${compiler.package_spelling(head)});
  if ((head == <struct> || head == <union> || head == <enum>) &&
      key.cdr() && !key.cddr() && tag is <string>)
    return %($head ${compiler.package_spelling(tag)});
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
    // A shallow parse reads emitted C, where generated spellings are the
    // compiler's own output rather than a source declaration.
    if (!_.shallow && _is_reserved_spelling(spelling)) {
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
  // Track file-local globals for protocol and static initializer checks. The
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
List Sym.bind_identity(Sym s, List context, List binding, List ast) {
  String spelling = binding_identity_spelling(binding);
  List key = context ? %(@context $spelling) : %($spelling);
  SymScope *scope = _semantic_scope(s, -1);
  Type annotation = ast.type_from_ast();
  scope.symbols[key] = annotation.declared();
  if (context === %(typedef)) {
    key = %($spelling);
    scope.symbols[key] = %(typedef $spelling);
    if (annotation.is_aggregate_tag() && (int) s.scopes.len() > s.base_scopes)
      s.binding_facts[%(ntype $binding)] = annotation;
    if ((int) s.scopes.len() > s.base_scopes)
      s.binding_facts[%(emitted $binding)] =
        s.compiler.fresh_name("local_typedef");
  }
  scope.bindings[key] = binding;
  if (!context && (int) s.scopes.len() > s.base_scopes) {
    s.binding_facts[%(automatic $binding)] = 1;
    s.binding_facts[%(type $binding)] = annotation;
  }
  return binding;
}

static Type _function_contract_type(Type type, int keep_qualifiers) {
  Array result = [];
  foreach (Var item, type) {
    if (item is <list>) {
      result.push(_function_contract_type(item, keep_qualifiers));
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
    %(method $binding), &stored) ? stored : NULL;
}

static List _binding_self_signature(Compiler compiler, List binding) {
  Var stored;
  return compiler.semantic_binding_facts().try_get(
    %(self $binding), &stored) ? stored : NULL;
}

// Record only prototypes reached in positioned full-parse source order.
static void _record_function_prototypes(
  Compiler c, Type declared_type, List items) {
  foreach (List target, items)
    match (target)
      case %(bind ?binding ?modifiers): {
        List single = %(declare $declared_type (bindings $target));
        Type type = single.type_from_ast();
        if (!type.is_function()) continue;
        /* A source attribute on the prototype belongs to the function; the
           generator writes it on the prototype it derives from the
           definition. */
        List attributes = NULL;
        foreach (Var item, modifiers)
          if (item is <list> && car(item) is <string>)
            attributes = attributes ? %( @attributes $item ) : %($item);
        if (attributes)
          c.semantic_binding_facts()[%(attributes $binding)] = attributes;
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

/* Reports a second definition of one file-scope name, which C rejects,
   when both sit under the same conditional arms. Definitions under
   different arms are not compared. For a variable, whose initializer moves
   into the generated init function, a duplicate under two true conditions
   is therefore not detected, and the later initializer wins. */
static void _report_redefinition(Compiler c, String kind, List binding) {
  Var arms;
  if (!c.semantic_binding_facts().try_get(%(arms $binding), &arms) ||
      !List.equal(arms, c.arms))
    return;
  String spelling = binding_identity_spelling(binding);
  c.report_error(
    <type>, %"$kind '$spelling' is already defined in this scope",
    c.token, %("prior definition: '$spelling'"));
}

static void _record_function_definition(
  Compiler c, Type type, List binding) {
  List contract = _function_completion_contract(
    type, _binding_method_identity(c, binding),
    _binding_self_signature(c, binding));
  Var stored;
  if (c.semantic_binding_facts().try_get(%(completion $binding), &stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    String spelling = binding_identity_spelling(binding);
    if (state_kind == <prototype>) {
      /* A definition without `static` after a `static` prototype keeps the
         prototype's internal linkage in C. */
      match (prior_contract)
        case %(function-contract ?a ?b static ?d)
          if (contract.equal(%(function-contract $a $b extern $d))):
            contract = prior_contract;
      if (List.equal(prior_contract, contract)) {
        c.semantic_binding_facts()[%(completion $binding)] =
          %(completed $contract);
        c.semantic_binding_facts()[%(arms $binding)] = c.arms;
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
      _report_redefinition(c, "function", binding);
  }
  c.semantic_binding_facts()[%(completion $binding)] =
    %(definition $contract);
  c.semantic_binding_facts()[%(arms $binding)] = c.arms;
  String spelling = binding_identity_spelling(binding);
  if (spelling && !type.is_static()) c.fn_defs[spelling] = 1;
}

static int _is_initializable_object_type(Compiler compiler, Type type) =>
  compiler.sym.is_string_type(type) ||
         compiler.sym.is_named_value_type(type, "List") ||
         compiler.sym.is_array_type(type) ||
         compiler.sym.is_map_type(type) ||
         compiler.sym.is_named_value_type(type, "Func");

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

static void _record_static_object(Compiler c, Type declared, List bindings) {
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
        Map references = {}, Array ordered = [];
        _collect_references(value, references, ordered);
        c.static_init_deps[binding] = ordered.list_free();
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

/* An initializer makes a file-scope declaration a definition; a tentative
   one may be repeated. */
static void _record_object_definitions(Compiler c, List bindings) {
  foreach (List row, bindings)
    match (row) case %(op = (bind (!set ?binding (binding ? ?)) ?) ?): {
      List key = %(defined $binding);
      if (c.semantic_binding_facts().contains(key))
        _report_redefinition(c, "variable", binding);
      c.semantic_binding_facts()[key] = 1;
      c.semantic_binding_facts()[%(arms $binding)] = c.arms;
    }
}

static void _record_top_level_function_state(Compiler compiler, List node) {
  match (node) {
    case %(declare (!set ?declared (*)) (bindings *bindings)): {
      Type type = declared;
      _record_object_definitions(compiler, bindings);
      _record_static_object(compiler, type, bindings);
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
  String name = key.car();
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
    Type declared = marker;
    if (!declared.is_typedef()) return type;
    Var target;
    if (!symbols.try_get(declared, &target)) return type;
    return _replace_type_base(type, base, target);
  }
  return type;
}

/** Binds a local aggregate tag before its fields, preserving native spelling.
    A reference reuses the nearest visible tag; a definition or standalone
    forward declaration introduces the tag in the current lexical scope. A
    macro template names its tags as template locals.
*/
Var Compiler.aggregate_name(
  Compiler compiler, Symbol kind, Var name, int definition) {
  Sym sym = compiler.sym;
  if (name is not <string> || compiler.parsing_source_syntax()) return name;
  if (compiler.macro_holes) {
    List local = compiler.macro_tag_name(kind, name, definition);
    return local ? local : name;
  }
  Type type = %($kind $name);
  if ((int) sym.scopes.len() <= sym.base_scopes) {
    /* Only a definition or standalone forward owns this package tag.
       A field or prototype may merely refer to a tag from a C header. */
    if (definition && !sym.get_exact(type))
      sym.declare(NULL, type, type);
    return name;
  }
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
int Sym.is_var_type(Sym s, Type type) => s.is_named_value_type(type, "Var");

/** Reports whether `type` reaches the named `String` value type. */
int Sym.is_string_type(Sym sym, Type type) =>
  sym.is_named_value_type(type, "String");

/** Reports whether `type` reaches the named `Array` value type. */
int Sym.is_array_type(Sym sym, Type type) =>
  sym.is_named_value_type(type, "Array");

/** Reports whether `type` reaches the named `Map` value type. */
int Sym.is_map_type(Sym s, Type type) => s.is_named_value_type(type, "Map");

/** Reports whether `type` reaches C's boolean type, `bool` or `_Bool`. */
int Sym.is_bool_type(Sym sym, Type type) =>
  sym.is_named_value_type(type, "bool") ||
  sym.is_named_value_type(type, "_Bool");

/** Reports whether `type` reaches a named value type before its definition. */
int Sym.is_named_value_type(Sym sym, Type type, String name) {
  // Stop at the named type instead of resolving through its typedef.
  if (!type || !name) return 0;
  Type wanted = %($name), origin = type.canonicalize();
  type = _resolve_key_helper(sym, origin, wanted, origin, 0);
  return type == wanted;
}

/** Returns an aggregate field's declared type, or `NULL`.
    A member of an anonymous struct or union belongs to its enclosing
    aggregate in C, so unnamed rows are searched the way a designated
    initializer already reaches them.
*/
Type Sym.lookup_field(Sym sym, Type type, List field) {
  type = sym.resolve_key(type);
  if (!type || !type.is_aggregate_tag()) return NULL;
  Type found = sym.get(%( @type @field ));
  if (found) return found;
  foreach (List row, sym.field_order(type).cdr()) {
    Type member = row.cadr();
    if (row.car().truth() || !sym.resolve_key(member).is_aggregate())
      continue;
    found = sym.lookup_field(member, field);
    if (found) return found;
  }
  return NULL;
}

/** Records declaration AST fields in source order after binding finishes.

    `Field` types already use member keys. Unnamed rows retain their type
    and an empty name so initializer traversal preserves anonymous subobjects.
*/
void Sym.declare_field_order(Sym sym, Type type, List fields) {
  Array rows = [];
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

static size_t _meta_align_up(size_t offset, size_t alignment) =>
  (offset + alignment - 1) / alignment * alignment;

static List _meta_type_layout(Sym sym, Type type, Map cache);

static List _meta_var_layout(Type declared) {
  size_t size = sizeof(Var), alignment = _Alignof(Var);
  return %(var $declared $size $alignment);
}

/* A scalar's Var tag may differ from its bytes' row only where the tag is
   fixed for the type, as Symbol's is for its unsigned-long code. A tag a
   unit's declared converter supplies may box something other than those
   bits. */
static List _meta_scalar_layout(
  Type declared, Type exact, NativeScalarAccess scalar, Symbol tag,
  Type tagged) {
  if (tag != scalar.tag && (!tag || tag != tagged.fixed_var_tag()))
    return NULL;
  return %(scalar $declared ${scalar.size} ${scalar.alignment} $exact $tag);
}

/* C's bool is one byte holding 0 or 1, and an enum whose enumerators fit in
   int is an int. Neither has a Var tag of its own; each value is the int C
   promotes it to. The parser records which enums fit, and an enum without
   that record has no layout. */
static List _meta_int_layout(Type declared, Type exact) {
  NativeScalarAccess scalar = native_scalar_access(exact);
  return %(scalar $declared ${scalar.size} ${scalar.alignment} $exact i32);
}

/* POSIX gives function and object pointers one representation, whose
   alignment is its size on every supported host. */
static List _meta_pointer_layout(Type declared, Symbol tag) {
  size_t size = sizeof(void *);
  if (!tag) tag = <p48>;
  return %(pointer $declared $size $size $tag);
}

static List _meta_record_layout(Sym sym, Type record, Map cache) {
  Var cached;
  if (cache.try_get(record, &cached)) return cached;
  List order = sym.field_order(record);
  if (!order) return NULL;
  Array fields = [];
  defer fields.free();
  size_t offset = 0, record_alignment = 1;
  foreach (List row, order.cdr()) {
    (String name, Type member) = row;
    List layout = name ? _meta_type_layout(sym, member, cache) : NULL;
    if (!layout) return NULL;
    (size_t size, size_t alignment) = layout.cddr();
    offset = _meta_align_up(offset, alignment);
    fields.push(%(field $name $member $offset $layout));
    offset += size;
    if (alignment > record_alignment) record_alignment = alignment;
  }
  size_t record_size = _meta_align_up(offset, record_alignment);
  List result = %(
    record $record $record_size $record_alignment @{fields.list()});
  cache[record] = result;
  return result;
}

/* Derives one immutable native layout from canonical Sym declarations. Every
   layout starts `(KIND TYPE SIZE ALIGN ...)`:

     (var TYPE SIZE ALIGN)                  a raw Var
     (scalar TYPE SIZE ALIGN EXACT TAG)     an exact C scalar row
     (pointer TYPE SIZE ALIGN TAG)          a data or function pointer
     (record TYPE SIZE ALIGN (field NAME TYPE OFFSET LAYOUT) ...)

   TYPE is the declared type, so a pointer to the object has the Var tag
   native code gives it. A scalar's EXACT row owns its bytes and TAG its Var
   value. A pointer with no Var tag of its own is carried as `<p48>`. */
static List _meta_type_layout(Sym sym, Type type, Map cache) {
  Type declared = type.declared();
  Type alias = declared.base_type();
  int hops = 0;
  while (alias && (alias.is_typedef_name() || alias.is_typedef())) {
    if (sym.get(%(@alias "layout-attribute"))) return NULL;
    alias = sym.next_typedef(alias, &hops).base_type();
  }
  if (sym.is_var_type(declared)) return _meta_var_layout(declared);
  Type tagged = NULL;
  Symbol tag = sym.var_tag_for_type(declared, &tagged);
  Type native = sym.normalize_declared_type(declared);
  Type exact = native.scalar();
  NativeScalarAccess scalar = exact ? native_scalar_access(exact) : NULL;
  if (scalar)
    return _meta_scalar_layout(declared, exact, scalar, tag, tagged);
  if (!tag && sym.is_bool_type(declared))
    return _meta_int_layout(declared, %(unsigned char));
  if (!tag && native.is_enum())
    return sym.get(%(@native "int-range"))
         ? _meta_int_layout(declared, %(int)) : NULL;
  type = sym.resolve_key(declared);
  if (type && type.is_pointer()) return _meta_pointer_layout(declared, tag);
  // A struct with a layout attribute has a C-owned native layout.
  if (!type || type.car() != <struct> ||
      sym.get(%(@type "layout-attribute")))
    return NULL;
  return _meta_record_layout(sym, type, cache);
}

/** Returns the evaluator's native byte layout for `type`, derived from its
    canonical Type identity and Sym-owned member order. Meta adoption remains
    a separate compiler decision and cache presence does not advertise it. */
List Compiler.meta_type_layout(Compiler c, Type type) =>
  _meta_type_layout(c.sym, type, c.meta_layouts);

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
  int count = c.names.counters.try_get(key, &stored) ? stored.int() + 1 : 1;
  c.names.counters[key] = count;
  return %((gensym $owner $count));
}

/** Pushes a new empty lexical scope. */
void Sym.push_new_scope(Sym sym) {
  struct SymScope scope = {
    .symbols = {},
    .bindings = {},
    .enumerators = {}
  };
  sym.scopes.push(&scope);
}

/** Pushes a caller-supplied lexical scope while retaining its map objects. */
void Sym.push_scope(Sym sym, SymScope scope) {
  sym.scopes.push(&scope);
}

/** Pops the innermost scope, or returns an empty scope when none exists. */
SymScope Sym.pop_scope(Sym s) {
  struct SymScope scope = { 0 };
  s.scopes.try_pop(&scope);
  if ((void *) scope.macros != NULL) s.local_macro_names -= scope.macros.len();
  return scope;
}

// constructed ast elaboration
