# Phase 3 logical capture interface prototype

## Verified result

The isolated dual-parser compiler builds and runs `probe.x` with exit 0.
Incremental `capture.patch` applies after phase2 `parser3.patch`; no production
source or dev publication changed. Helper and executable are ordinary x2c.
Root can run its combined isolated compiler with `run <absolute probe.x>`.

* `case pattern(?type)` now captures a singular logical Type as a Var containing
  its ordinary canonical Type List, despite its internal splice representation.
  Actual source producer `$type_round(sizeof(int))` recognizes, reconstructs
  through the same `$size` descriptor, and ordinary insertion executes 4.
* `$ordered_round(3 + sizeof(int))` uses descriptor formals `(Type, Expr)` but
  body occurrence order `(Expr, Type)`. Dynamic source case receives the correct
  logical values and construction executes 7. Separate reversed arithmetic
  formals test also passes.
* Actual Statement capture `$stmt_round(return 9;)` recognizes, reconstructs
  through the same returned descriptor, recognizes the constructed singleton
  sequence automatically, and produces exactly the same Expr capture (1).
  Direct return nodes and singleton `(seq return)` root forms match. No manual
  `.cdr().car()` extraction remains in the successful test.
* Repeated Expr hit/miss 1/0, Expr sequence empty/three reconstruction 0/3,
  Name member capture/reconstruction 1/1, and correlated repeated member Name
  equal/different labels 1/0 all pass.
* Existing meta-template-calls fixture remains 14 8 11 / 91 2 91 / 42 42 3 2.
  Named Expression macros retain existing meta computation behavior.
* `git diff --check` passes in isolated worktree. Focused build/probes only:
  no broad gate, bootstrap refresh, publication, corpus or performance claim.

## Shared owners and mechanics

Macro_pattern produces a normal Match List. The existing MatchCaptureLayout
analyzes both that body pattern and the logical call argument layout. The
private callback invokes the existing x2c_match_try_capture, materializes Type
internal spans through existing Match, then remaps actual body-order slots into
logical case slots. Results publish only after success. No second matching
machine or semantic AST validator was introduced.

Compiler source case lowering uses private `_macro_case_pattern` carrying the
ordinary callback expression explicitly. That reference keeps native helper
reachability correct. Compiler.match_pattern_value derives logical layout from
its names. Emitter emits the callback with subject, descriptor, names and the
existing capture buffer. All ordinary Match case lowering stays unchanged.
This prototype compiler/helper ABI is provisional private machinery, not a new
public operation or pseudokeyword.

Singleton Statement root normalization is the explicit pattern alternative
`(!or statement (seq statement))`, only for block-item descriptors with exactly
one seq item. Multi-item sequences and explicit blocks remain distinct.
Construction removes only parser hole shell `(expr (<macro-expr>) (expr ...))`
after replacing that slot; literal payloads are skipped. `_macro_instantiate`
owns structural substitution and child inlining; Macro_apply delegates in this
standalone probe, ready for stages worker to replace it with pending ordinary
compiler-owned construction. Introduced local hygiene is not claimed here.

Anonymous captured Macro classification now uses existing semantic binding type
facts keyed by binding identity, replacing phase2 spelling lookup.

## Remaining boundaries

Type inputs are canonical parser-level syntax Lists, not independently checked
types; ordinary compiler insertion retains binding/typing authority. Typedef
alias equivalence and bound/lowered type recognition are not proved by these
probes. Equality is structural for captured expressions in this worker; alpha
and cross-hole binding relations belong to binding worker integration.

Repeated Name *member* labels are correlated. A single Name used in declaration,
resolved reference and member positions needs role-specific capture projections:
raw program-binding identities and member spellings cannot simply share one
raw Match slot. This mixed-role normalization has not been implemented/tested
here; it requires existing producer capture rows and compiler binding facts.
The helper still substitutes expression/value/source rows simplistically.

The adapter maps internal Type binder `*name` from logical `?name`. Production
should allocate internal slot names from formal identities, preventing collisions
between logical Type captures and same-labelled explicit sequence captures.
Unused formal holes cannot discover values: current callback returns a miss
if requested internal capture has no slot/presence. The public contract for
unused-hole case arguments remains a design decision, not type validation.
Duplicate logical capture labels across different hole kinds also need a
consistent projection/equality rule before production.

The callback re-analyzes layouts per match. This is sufficient bounded evidence;
production can reuse existing prepared/cache layouts rather than add new caches.
These probes preserve stage distinctions but do not prove generic typed
Statement sequence captures, declaration-bearing Name normalization, or every
native helper free-reference domain. No broad failure of the dual-use approach
is inferred from those unimplemented projections.
