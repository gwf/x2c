/*  compiler.x -- one x2c unit's translation state and its two parses

    Copyright (c) 2025 Gary William Flake.

    A `Compiler` owns the translation state of one unit: its token cursor,
    symbol table, and declaration state. Collection parses the unit
    shallowly, skipping function bodies; the full parse produces its AST.
    The related compilers of one unit share its package registries,
    generated names, and binding numbers. The symbol table is `Sym`, in
    `symtab/symtab.x`.

    Diagnostics may exit immediately or raise `<malformed>` while a recovery
    boundary is active.
*/
#pragma once
#include "private-keywords.x"
static keyword loop $private.loop;
#include "tokenizer.x"
#include "ast.x"
#include "type.x"
#include "logger.x"
#include "sourceview.x"
#include "meta.x"

/** Names the positioned diagnostic store routed by a `Compiler`. */
typedef struct Diagnostics *Diagnostics;

/** Names a unit's compile-time callables, in `meta-native/bindings.x`. */
typedef struct MetaBindings *MetaBindings;

/** Names the C preprocessor state at one point of a source, in
    `cpp/cpp.x`.
*/
typedef struct Cpp *Cpp;

/** Describes the `#!` script unit a translation unit was started from: its
    canonical path, its first line as written, and whether it defines `main`
    itself. Every compiler of that unit shares one record, so collection sees
    the same script settings the full parse does.
*/
typedef struct ScriptUnit {
  String path, shebang;
  int defines_main;
} *ScriptUnit;

/** Describes an x2c source whose `module` block names member files: `text`
    holds the file's own text, `own`, with each member's text in place of the
    block. `markers` are the line-marker rows that give each region of
    `text` its file, line, and byte offset there, with the text that
    precedes that offset on its line and the prefix that file's statics
    take. The first row marks the start of `text`. `members` maps each member's
    canonical path to its content hash.
*/
typedef struct ModuleSource {
  String text, own;
  Array markers;
  Map members;
} *ModuleSource;

/** Holds scope-owned generated-name state shared by related compilers.

    `Compiler.new` initializes every valid instance; callers borrow it from
    the compiler rather than constructing or freeing it. `next_binding` is
    the last binding identity issued in the translation unit: collection,
    shadow, package, and full-parse compilers all draw from it, so a binding
    number names one live declaration across every symbol table in the unit.
    Exported rows use their interface's own numbering, which starts at 1;
    imported templates rebind those references in the consuming unit.
*/
typedef struct GenNames {
  Map counters, adapters, file_scope_owners;
  int next_binding, issued;
} *GenNames;

/** Holds the mutable maps that form one lexical semantic scope, and the
    number of alias rows it defines.

    Active scopes have initialized maps. The zero value is only the sentinel
    returned when an empty scope stack is popped.
*/
typedef struct SymScope {
  Map symbols, bindings, enumerators, macros;
  int aliases;
} SymScope;

/** Counts the destinations `Pending.area` names; area 0 is unit support. */
enum { PENDING_AREAS = 5 };

/** Holds generated code awaiting insertion, by `Pending.area` destination:
    unit support declarations, which `Compiler.transform` lowers after the
    unit, then the lowered statements of each file initialization area.
*/
typedef struct Pending { Array areas[PENDING_AREAS]; } Pending;

/** Holds each destination's length for `Pending.restore`. */
typedef struct PendingMark { int lengths[PENDING_AREAS]; } PendingMark;

/** Names the scope-owned semantic table belonging to one compiler. */
typedef struct Sym *Sym;

/** Names the slots a rewrite's first lowering watches; see "prepared
    replacements" in macros.x.
*/
typedef struct SlotWatch *SlotWatch;

/** An enclosing syntax construct returned by `x2c_enclosing`: a
    function body with its declaration in `node`, and `lowering` set while
    the transform lowers it, a block item with the token or origin it
    starts at, or an initialized declarator with its declaration base in
    `base` and its `(bind ...)` node in `node`.
*/
typedef struct Ancestor {
  Symbol what;
  Token token;
  // A function row is a `callback` when the kernel wrote it for a finalizer.
  int origin, lowering, callback;
  List base, node;
} Ancestor;

/** Holds mutable state for one source translation.

    The structure, its state, and its owned compile-time bindings belong to
    the current `Scope`. `Compiler.free_bindings` permits early cleanup;
    otherwise Scope teardown releases them. All their calls must return
    first.
*/
typedef struct Compiler {
  String filename, text, root_dir;
  /* Package-mode unit: NULL outside. package_dirs holds import search roots;
     package_source_dirs holds the explicit roots that select source ownership.
     package_roots holds each collected package directory, package_aliases each
     resolution-only spelling alias -> package name, package_members each
     `with` local spelling -> (package member), and package_effects each
     collected package's public compile-time definitions in include order. */
  String package, List package_dirs, package_source_dirs;
  Map package_roots, package_aliases, package_members, package_effects;
  Token token;
  // Optional end of supplied input; NULL keeps ordinary file diagnostics.
  Token input_boundary;
  Tokenizer tokenizer;
  /* For the host preprocessor's merged output, the file each region came
     from, as `(position text-line file line)` rows; NULL otherwise. A
     module's rows add the region's byte `offset` in that file and the text
     before it on its line. */
  Array line_markers;
  // The unit's text when its `module` block was spliced, or NULL.
  ModuleSource unit_source;
  List return_type, include_dirs;
  /* File paths map to content hashes or 1 when text is not embedded.
     Include-search candidates map to absence or their resolved identity. */
  Map deps;
  List aggregate_type, macro_stack, Sym sym;
  /* The last binding identity issued before the outermost active expansion
     began; a later identity was introduced by that expansion. */
  int expansion_floor;
  SymScope params;
  Map key_ids, macros, kw_aliases;
  /* The `$lisp.binding` rows of the unit's macro state, each
     `(group name function type)`, newest first, and the groups
     `$lisp.install` has installed. */
  List binding_rows, binding_sealed;
  /* `#define` names this unit has passed, for the literal warning and for
     declaration prefixes: the `List` of specifier words of a body made of
     specifiers and attributes, `<string>` for a string literal,
     `<annotation>` for a function-like attribute macro, `<wrapper>` for one
     that wraps its parameter in prefixes, else 1. A name the preprocessor
     expands never reaches the parser, so only the names it leaves to C
     are read as prefixes. */
  Map object_macros;
  /* The preprocessor state the next expansion starts from, or NULL for
     the macros visible before the file's first line, and the
     `Compiler.command_macros` rows of the unit's `-D` and `-U` options. */
  Cpp cpp;
  List command_macros;
  /* Module discovery prepares its root's included macro exports only when
     preprocessing first reaches an include. Collection children do not
     inherit this transient request. */
  String macro_export_source;
  // Discovery-only CPP/include parts; never semantic collection entries.
  Map macro_export_parts;
  /* The open conditional groups at the current top-level form, each an
     `(id arm state)` entry, so one function defined in two arms of one `#if`
     is one definition. `arm_stacks` maps each conditional directive's token
     index to the groups open after it. */
  List arms;
  Map arm_stacks;
  // Token indices around attributes that can change native record layout.
  Array layout_marks, packed_marks;
  /* The cursor after a governed statement took the directives before it,
     which the following item must not read again. */
  Token directives_taken;
  Map protocols, conforms, protocol_helpers;
  /* Results derived from the occurrence and adoption tables. Publishing a
     protocol or adoption drops the whole map because those results change. */
  Map proto_cache;
  // Visible protocol adoptions indexed by base and participant.
  Map adoptions;
  Map macro_holes;
  // Open declaration bodies whose aliases end at their closing brace.
  int alias_level;
  Map local_macro_captures;
  /* Depth of macro value applications being bound; their transactions
     also cover effects and code-value carriers are consumed. */
  int macro_application;
  List lambda_scopes;
  Array match_types;
  /* While the full parse runs, the effects each file the unit includes
     delivers at its include line, by the file's canonical path. */
  Map included_effects;
  Map init_tokens, static_init_deps, fn_defs;
  Array id_keys;
  String init_fn, fini_fn;
  Pending pending, int prelude;
  /* `meta_comptime` names the `meta` functions that reach a `Meta`
     operation and so have no runtime form at all: no unit emits one.
     `meta_regions` maps each installed one to its region summary, which
     the lifetime check of a later `meta` function reads at its calls.
     `meta_hashes` maps each function definition to the hash of its text,
     which a `meta` definition and its copy linked into the compiler must
     share. Collection hashes this unit's bodies before they are parsed;
     `meta_calls` lists each parsed definition's referenced names. */
  Map meta_comptime, meta_regions, meta_hashes, meta_calls;
  // An independently loaded source can keep its own compiled helper.
  struct MetaHelper *meta_helper;
  /* Native functions that included units advertise with `meta`, by name,
     holding each declared signature. A function binds into the macro
     session the first time compile-time code calls it. */
  Map native_meta;
  // Public project meta signatures and their defining source files.
  Map project_meta;
  /* The unit's top-level nodes parsed so far, and its `meta` group in
     source order: each bodied `meta` function as `(function FN NAME
     TYPE)`, and while the project meta build parses the unit or the REPL
     stages it, each `meta static` value as `(static DECLARATION)`, and while
     the project meta build parses it, each placeholder for a call left for
     the translation as `(later PLACEHOLDER)`. `meta_group_bound` holds the
     names the REPL bound to staged native code, the modules it reset, and
     each bodyless `meta` prototype nothing supplies. */
  Array unit_nodes, meta_group;
  /* Each bodied `meta` function the unit spells, as `(name line)`, for
     the definitions dump. */
  Array meta_definitions;
  Map meta_group_bound;
  /* Zero for ordinary parsing, one for metadata collection, or the
     project helper table index plus one. */
  int meta_build;
  /* One plus the unit node count before the first form a full parse
     skipped, or zero. */
  int skipped_form;
  int load_source;  // Expose the loaded unit's public functions.
  int runtime_inc, runtime_hdrs, collect_protocols, shallow, source_private;
  int module_declaration;  // Parsing a `module` declaration.
  int replaying_declaration;  // Binding a collected declaration's syntax.
  int public_bodies;  // Cold interfaces bind only exposed inline bodies.
  int interface_provider, signature_only;
  int collection_native;  // Declaration collection executed project meta code.
  Map collection_native_files;  // Providers collected in this unit.
  Array pending_inline_bodies;
  /* Whether the source is in the indentation syntax whatever its name, as
     when collection parses a segment of a file whose pragma it saw. */
  int layout;
  /* Whether the body being parsed belongs to a `meta` function, which is
     what lets a call to a compile-time-only one be refused everywhere
     else. */
  int meta_body;
  // A Unit target retains meta code and complete initializers.
  int capture_unit;
  List active_rewrites;
  /* The rules active while a rule's meta function runs, that rule first;
     see `_written_support` in macros/rewrites.x. */
  List applying;
  Map rewrite_rules;
  /* Each rewrite replacement lowered once in this unit, by its template and
     slot signature, and the slots its first lowering watches. */
  Map prepared_rewrites;
  SlotWatch slot_watch;
  /* Where the expression statement being parsed starts. A meta call there
     that the statement's `;` ends is evaluated as the statement. */
  Token meta_statement;
  /* A collection pass whose protocol registries are installed from collected
     symbols on first use; `_install_imports` owns the installation. */
  int import_protocols;
  int in_pattern, match_is, runtime_literals, inline_header;
  // In-process native modules retain their cached constants for the process.
  int permanent_literals;
  int builtin_defs, in_proto, macro_count, recovery_depth;
  int declaration_produced;
  // Set when a cleanup region needs the exception runtime declarations.
  int needs_exception;
  int local_macro_capture_scopes;
  // Linkage groups that earlier segments of the collected file left open.
  int open_linkage;
  String fn_name, Diagnostics diagnostics, Array braces;
  /* The `Ancestor` rows of the syntax being parsed, innermost last, and
     the code placed after a block item or initialized declarator, each
     `(depth binding result code)`: the item's row index, the declarator's
     binding or nil, and the placing expansion's result. */
  Block ancestors;
  Array placements;
  // Where each line of `lines_text` starts, for showing diagnostic lines.
  String lines_text, Array line_starts;
  /* The unit's script record, and the same record on the compiler whose own
     file is that script; both NULL for an ordinary unit. */
  ScriptUnit unit_script, script;
  MetaBindings meta_bindings, int borrowed_bindings;
  GenNames names;
  Array origins, int origin, source_map;
  int dump_expansions;
  // The request view outlives the unit; semantic stores die with this unit.
  SourceView sources;
  int source_facts, source_primary;
  Array source_occurrences;
  // Borrowed only while a named-type body captures its physical references.
  Array source_capture;
  Map source_definitions, source_declarations, source_texts;
} *Compiler;

/** Holds one reversible semantic transaction in caller storage.
    The zero value is inactive. Keep an active transaction in one object;
    copying it does not coordinate completion. The symbol table's undo log
    holds the rows it may restore from `mark`; the staged generated-name
    counters and other snapshots live in its initial Scope.
*/
typedef struct SymTxn {
  Compiler c;
  int scope_index, next_binding, active, String initializer_name;
  String shutdown_name, Map counters;
  int local_macro_names, mark, meta_group_size, ancestors, placements;
  SymScope scope;
  Map statics, binding_facts;
  Map source_definitions;
  int source_occurrences;
  Array source_capture;
  int source_capture_length;
  /* A macro value application also stages producer effects: adapters,
     base bindings, pending code, origins and errors. */
  int extended, Map adapters;
  PendingMark pending, int origin_count, origin, needs_exception;
} SymTxn;

#include "diagnostics.x"
#include "symtab/symtab.x"
#include "preprocess.x"
#include "cpp/cpp.x"

protocol Var(Compiler) as void *;
#include "grammar.x"

#include "utils.x"
#include "parse/parse.x"
#include "protocol/protocol.x"
#include "macros/macros.x"
#include "stage.x"
#include "meta-group/meta-group.x"
#include "meta-helper-client.x"
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fields.x"

module {
  "lifecycle.x",
  "parsing/parsing.x",
  "declarations/declarations.x",
  "source-locations.x",
  "names.x",
  "pending.x",
  "binding-facts.x",
  "literal-cache.x",
  "patterns.x",
  "source-files.x",
}
