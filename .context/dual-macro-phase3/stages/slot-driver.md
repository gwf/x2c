# Slot functions, rule traversal, and measured control

## Working bounded meta driver

`driver.x` uses the four-form Macro surface: named `$bare` reference and
`case rule()` inside a rule-set loop. `fill_return` returns the current
lowered-only Var void return node. The meta driver replaces bare returns
through a nested if but preserves a nested lambda unchanged, matching
`src/transform.x:1422-1435` `_block_returns` semantics. It checks structural
output against the existing canonical return builder and unchanged-node
identity on a second pass. Native helper compilation and executable pass:
"meta rule driver normalizes bare returns and preserves nested lambda".
This is a rule-set traversal demonstrator with one active rule, not a
compiler migration or byte-identical compiler use. Its child rebuild copies
the Ast.rewrite_children algorithm solely in the isolated helper fixture;
production must export/reuse that existing owner instead of keeping both.

Recommended driver: local ordered rule selection, explicit prune decision,
then copy-on-change child recursion through Ast.rewrite_children. A rule
returns code plus ordered effect data; rule selection stops at first hit.
No-match leaves identity unchanged. Caller chooses preorder/postorder and
whether replacement is revisited; fixed-point use requires caller-specified
termination rather than silently expanding arbitrary meta computations.
Semantic boundaries (lambda bodies, cleanup regions, scoped bindings) are
prune/context facts, not guessed by generic List recursion. The current
fixture validates nested-lambda pruning only. Typed dispatch remains a slot
function called with ordinary compiler-provided facts, not pattern matching
against guessed type spellings.

## Facts pure slot functions require

Pass resolved source/expected Type and conversions already decided by the
ordinary compiler; issued declaration/reference Name identities; resolved
runtime-helper typed Exprs; current origin record; memo key and explicit
cache-hit value/absence; scope and cleanup ancestry/targets needed by the
specific lowering. `_direct_func_adapter` transform.x507 uses canonical Type
and binding in its key; `maybe_adapt_func_arg`545 resolves/adapts before shape
construction. These decisions cannot be replaced by helper-side spelling
or callbacks. Input facts must be the facts the ordinary owner already
computes, not an independent helper semantic validator.

Requests that need a result midway (fresh issued Name, newly resolved helper,
or cached adapter required by a later slot) need compiler preparation before
the pure call, or a compiler-owned staged plan that executes one dependency
step then passes its produced fact to the next pure step. One helper call
cannot request an effect and simultaneously read its future result without
such a dependency representation. No helper compiler query is proposed.
An ordered effect plan is viable but not prototyped by this driver.

## Effects and rollback limitation

Existing SymTxn stages scope maps, binding facts, name counters, binding
allocation, initializer names and optional source facts (compiler.x2584),
but not early_decls or names.adapters. `add_early`2506 appends immediately;
`adapter-memo.xmacro` writes names.adapters immediately. Existing transaction
rollback therefore does not prove rollback of those proposed effects.
Proposed smallest extension: keep early declarations and memo writes in a
caller-owned pending batch, expose that batch's memo overlay during this
expansion, and publish only after successful insertion. Already-covered
name/binding operations run under existing SymTxn. Cleanup placement is an
ordered output/code construction decision informed by Walk ancestry, not a
global append effect. Origin restoration must remain dynamically scoped.
Rollback and intra-expansion memo visibility need focused failure probes.

## Actual measured bound-hole try control

After correcting statement categories/root seq and definition-only origin
wrappers, baseline and candidate have identical outcomes and raw C/H bytes
on all 62 cases: 46 lexical-try fixtures (38 pass, 8 expected negatives), plus
seven-file actual translation benchmark and exception-hot-paths in default
and live modes. Same source paths and explicit common X2C_HOME. No output
normalization. All final timed artifacts also match.

Five alternating paired samples after warmup, medians in seconds:

| Translation group | Mode | Direct builder | Template control | Change |
|---|---|---:|---:|---:|
| Seven compiler/tokenizer files | default |6.113|6.146|+0.54%|
| Seven compiler/tokenizer files | live |7.501|7.496|-0.07%|
| exception-hot-paths | default |0.591|0.589|-0.37%|
| exception-hot-paths | live |0.652|0.679|+4.25%|

Ranges overlap; short exception live samples are noisy. This establishes
feasibility of this compiled-in bound-hole skeleton, not a precise overhead
claim. It does not measure full meta slot calls/effect plans, open free-name
resolution, whole-compiler migration, native exception runtime performance,
allocations, or cold helper compilation. No recurring gate is added.
Prepared-once candidates: parsed macro descriptor and role layout,
MatchCaptureLayout/lowered Match program, hole projection/substitution plan.
Cache keys must include template shape and stage/role layout. Bound values,
issued names, origin and transaction effects remain per insertion; caching
them would leak units or scopes. Those preparation changes are proposals,
not optimizations proven by this timing.
