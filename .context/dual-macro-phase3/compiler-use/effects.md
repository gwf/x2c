# Effects-as-data boundary audit

Revised request read from attachment Pasted text.txt. This is research, not
production. Executable current-SymTxn probe saved in effect-rollback-probe.x,
fixture and complete result log beside it. Stable reproducible binary is
`/tmp/x2c-dual-open-parser2` (before later open producer fix).

Command:
```
X2C_HOME=/Users/gary/.codex/worktrees/agent-dual-transport/x2c \
X2C_PROTOTYPE_TXN=1 /tmp/x2c-dual-open-parser2 translate \
--out-dir /tmp/dual-try-smoke \
/Users/gary/.codex/worktrees/dual-macro-match-probe/x2c/.context/compiler-boundary/open/txn.x
```
1 means correctly rolled back:
`binding=1 fresh=1 early=0 init=0 memo=0 global=0 origin=0 exception=0`.
Probe restores leaked state explicitly afterward; that cleanup is NOT evidence
that SymTxn owns the missing fields. It performs real effects inside an ordinary
local semantic scope and caller-owned existing transaction.

## Existing owner and proposed records

| Operation | Current owner | Proposed effect datum | Apply point |
|---|---|---|---|
| Early helper publication | Compiler.add_early compiler.x2507 | `(early CODE)` | stage append; publish upon successful insertion |
| Initializer queue | Compiler.add_init compiler.x2514 | `(init PHASE CODE)` | same owner, ordered staged append |
| Adapter reuse/publication | src/adapter-memo.xmacro | `(adapter KEY RESULT CREATE_CODE)` | compiler consults memo; applies only selected creation effects |
| Private emitted name | Compiler.fresh_name compiler.x653 | `(fresh TOKEN ROLE)` | allocate in transaction; substitute TOKEN via existing holes |
| Binding identity | Sym.introduce compiler.x3043 | `(introduce TOKEN NAME_TOKEN)` | transaction binding owner; replace shared occurrences once |
| Target helper ref | Sym.resolve_global/reference_global compiler.x3014 | `(global TOKEN NAME)` | base-scope transactional owner; return value through TOKEN |
| Caller diagnostics | Walk.origin and Compiler.origin | `(origin SITE CODE)` | scoped insertion/at wrapper, never definition file position |
| Exception header need | needs_exception transform.x2420+ / generate.x1183 | `(need exception)` | staged flag; publish successful expansion only |
| Cleanup order | _inside/_unwind/_transfer transform.x1698-2473 | `(cleanup REGION CODE)` / placement request | region driver decides paths; meta producer builds CODE only |

Records are ordinary Lists outside the program AST. Tokens reuse template hole
replacement machinery. Meta helper functions receive facts/arguments and return
code plus records; they never query Compiler. The compiler applies effects.
Do not turn the table into another type/scope resolver or AST validator.

## Rollback gap and viable integration

SymTxn compiler.x2574-2700 snapshots current scope, statics, binding facts,
next_binding, name counters, local macro count, init/fini names, and sourcefacts.
It stages only current scope maps. reference_global can mutate a BASE scope
binding map while transaction scope is local. Rolling back counters without
removing that binding can leave a record whose numeric identity is later reused.
Early_decls/inits lengths, names.adapters, names.file_scope_owners, origin,
origins length, needs_exception are absent. No existing commit claim covers them.

Extend the existing caller transaction, not create a parallel validator:
stage touched base/current semantic maps, append queues and memo deltas; snapshot
fresh/file-owner counters and generated-origin additions. Effect dependencies
that need binding/name results before binding run against staged maps. Publish
queue/memo entries only after binding succeeds; any failure discards all deltas.
Preserve original Map owner identities on commit as current SymTxn.commit does.
Origins are preferably lexical/scoped application context; if an effect appends
origin records, their length/rows must be covered. Fresh and introduce should be
one effect or sequential dependency so a fresh unused emitted name is not leaked.

## Mid-template query facts

_adapter_helper queries target global signature/type (transform.x318);
_type_literal normalizes/caches declared Type (326); Func conversion branches
read canonical signatures, numeric/alias conversion facts, addressability, and
adapter cache presence. Existing compiler must pass those facts as arguments or
select the producer before template application. A meta process cannot infer
those facts from names alone. Adapter presence can be a compiler-selected effect
branch with a prebuilt create recipe; no helper query required.

Region cleanup placement needs current region ancestry, transfer target,
finally/handler presence, and already rewritten cleanup. _try_block already
receives body/clause/frame/handle/cleanup/bodies; _defer_block receives env,
callback, records, record, cleanup. Pass these facts, keep control-flow analysis
and placement in current region driver; templates own shape.

## Stage carrier recommendation

Internal borrowed carrier `(slot (stage source|bound|lowered) (value CODE)
(effects RECORDS))`; this is NOT a second AST. User lowerings use four forms and
meta slot calls, never read marker fields. Compiler-created slot interface
carries the stage supplied by producing operation. Source slots use ordinary
bind_syntax; bound/lowered slots short-circuit recursion but retain existing
binding/Type/source records. Expr parent still owns requested conversion; stage
alone must not suppress return/argument conversion. Context placement stays
ordinary AstPos ownership; no origin certificate or recursive AST validator.

The control proves exact-hole short circuit, fixed skeleton binding, and
retained lowered returns/source origins. It does not yet prove automatic public
meta-slot effects aggregation, a transaction-extension rollback implementation,
all stage positions, or parent conversion for bound Expr holes. Cache literal
writes, diagnostic output, parser token movement, imports/project/native side
effects are NOT covered by current SymTxn or by this proposed bounded delta
list. Either pass already prepared values or explicitly classify these as
unsupported effects until the existing owners supply rollback semantics.
