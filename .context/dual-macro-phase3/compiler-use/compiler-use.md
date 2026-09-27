# Compiled-in template control and open policy audit

Isolated checkout: `/Users/gary/.codex/worktrees/dual-macro-match-probe/x2c`.
No production edit, commit, bootstrap regeneration, gate, fetch, or push.
The incremental patch applies after phase-3 parser/capture and Match relation
patches. Build used `/tmp/x2c-dual-compiler-baseline`, a saved working binary:
`make -f ../stage.mk -C builds/0 X2C_COMPILER=/tmp/x2c-dual-compiler-baseline`.
Build passed. Initial translation-only smoke missed an invalid root `seq`
and Expr holes receiving Statement values. The repaired source uses Statement
holes and unpacks the singleton root `seq` through existing Match.
Actual `defer-try-cleanup.x` native build then passed and executed with output
`17 1 1 23`. Generated C exactly matched the baseline C (empty raw diff).
`src/transform.x` translation also passed. Full corpus belongs to transport.
Both compiler invocations must share explicit `X2C_HOME` to prevent different
worktree resource discovery; comparing identical source paths alone was
insufficient. The earlier corpus inherited-def failures and absolute-vs-relative
error-site paths disappeared when using the same agent-dual-transport home.
No output normalization was used.

## Demonstrated

Actual parsed `macro Statement $compiler_try_shape(...)` compiles into compiler
binary as a Macro descriptor, used at runtime by `_try_block`. Its body is
ordinary source containing `if (!$condition) $body else ...`, shared canonical
macro AST. Descriptor parameters derive substitution keys. The skeleton is
consumed by ordinary `Compiler.bind_syntax`, not emitted directly.

Existing typed declarations, expressions, transformed body/landing/cleanup
enter temporary local slots. A per-Compiler map short-circuits exact slot
nodes before recursive binding. This preserves existing binding records,
returns, source wrappers, declaration publication, and Type identities.
Expression shells around holes are slots too; enclosing fixed `!` and `if`
remain bound by the compiler. Scope map lifetime is one synchronous call.
No new AST language, semantic resolver, origin authentication, or validator.

Runtime functions and types remain existing typed Expr/Statement holes, so
this control proves the compiled-binary and bound-hole boundary, **not open
free-reference semantics**. Declared Name IDs and emitted names are existing
region owners; there are no new fixed-local names in this control. It does
not yet prove caller-selected return conversion or arbitrary hole positions.

## Open contract critique

`macro open` is a viable explicit definition modifier. Closed remains default.
The word must mean target-unit global resolution, not arbitrary lexical lookup.
Sym.reference_global (compiler.x3020) already resolves/creates base bindings;
ordinary Sym.reference includes caller locals. Definition producer must retain
which identifiers are fixed locals, holes, and free references. A source-name
replacement over all nodes would destroy these roles.

Type strings cannot merely remain unresolved: parse.x2195 `_finish_type`
unconditionally calls Sym.local_type; compiler.x3686 walks local typedef and
tag scopes. Open Type roles need producer-known base-scope Type projection
and a bound Type slot; `_typedef_target`3742 is already base-only. An open
value policy does not settle typedef or tag namespaces.

Some current lowering callees are native String calls (expressions.x2306)
and types become visible only in generated exception.h (generate.x1178).
Resolving them as ordinary source calls may require signatures absent from
semantic context, cause conversions, or emit a different callee shape.
Retaining existing typed call Expr holes is a concrete viable alternative
for the initial compiler migration. New declarations/callees/Type context
must remain owned by ordinary target Compiler; no ambient compiler singleton.

Byte-identical names require issued Name holes or the original fresh-name
stem/order: compiler.x653 allocates per-stem `_x2c_<stem>_<count>`; macro
introduced bindings use `macro_<source>` (macros.x2707), so ordinary macro
freshening does not automatically preserve region names.

Stage must be explicit: bind_syntax consumes parser-shaped return with TYPE
(parse.x2738), while region lowering emits two-field return (transform.x2473).
Already-lowered Statement holes must bypass rebinding. Skeleton source origins
resolve m-origin under caller origin; retained hole at wrappers must survive.

## Not investigated/proved by this patch

Genuine `macro open` parsing/producer roles, compiled-in fixed free identifiers,
base-only Type holes, anonymous open macros, Expr hole parent conversion,
source-location equality over the broader compiler corpus, generalized bound
hole interfaces and exact private slot collision/lifetime contract. A failure
of this control would reject this control, not open templates as a design.

Generalizing the retained-slot boundary must preserve AstPos placement checks
using producer parameter roles and existing placement machinery. The control
trusts its fixed parsed callsite and therefore does not demonstrate rejection
of a bound Statement inserted at an Expr/Field/Unit slot. A private slot table
must also distinguish nested applications and sequence-row projection rather
than treating arbitrary matching Lists as ownership certificates. Canonical
AST construction remains legal without authenticating origin.

A no-extra-modifier alternative is an explicit `Macro_open(t)` descriptor
projection selected by the compiler caller. It avoids grammar changes but can
reinterpret closed captures contrary to definition intent; a definition
modifier documents free-role intent earlier and is the recommended public
boundary. Neither choice alone supplies global Type namespace projection.

## Full control validation update

Transport worker verified all 62 comparison cases have identical exit outcomes
and raw generated bytes after repair, using common explicit X2C_HOME and exact
source paths. Manifests: `/tmp/dual-try-common-baseline/manifest.json` and
`/tmp/dual-try-origin-candidate/manifest.json`. No output normalization.

After the first category/root fix, 59/62 bytes matched; three fixtures still
changed ErrorSite line/file because definition-produced `at m-origin` wrappers
resolved to zero and reset emission context. The control now removes only those
wrappers from the macro body BEFORE substituting bound holes, through existing
List.search_replace. Existing `_rewrite`/outer `at` remains insertion origin
owner; every supplied hole at/src wrapper and source marker is preserved.
This restores the original hand-constructed skeleton's location behavior.

The 62 cases comprise 46 try fixtures (38 expected-success, 8 expected-negative)
and 16 default/live corpus translations (seven compiler/tokenizer sources and
exception-hot-paths). Raw emitted-byte parity does not establish behavior for
all compiler features or prove open free-name semantics.
