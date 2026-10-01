# Compiler and library: the next beautification pass

> Status: done, 2026-09-30, as PR #72 (2685655f). Remaining organization work
> moved to [x2c-source-organization.md](x2c-source-organization.md).
>
> Earlier status: implementation campaign complete, 2026-09-30.
> The merged mitigation is PR 71, origin/dev b56a9ac2.
> Packets 1-12 are implemented, including Gary's approved runtime CRLF dedent
> behavior and quasiquote form/sequence repair. Packet 13 completed bounded
> state/construction review and implemented source rendering and operation-local
> metadata/initializer reuse; no state representation redesign or allocation-
> failure certification is claimed. Combined publication evidence and retained
> coverage limits are recorded with the campaign PR.
> The designs below retain their original evidence boundaries.

## Goal and current architecture

Make complete operations brief, direct and coherent through current x2c:
one owner for a semantic fact, one representation where identity permits it,
and a visible lifetime for each acquired resource. A smaller helper or a
higher macro count is not the objective. Compiler and core library are the
primary scope; optional package design remains separate.

The compiler already has a strong shared language pipeline: CliRequest and
Frontend configure a source unit; parsing constructs canonical syntax;
binding, types, protocols and regions establish semantic facts; transformation
uses those facts; generation, emission and formatting produce native code.
Source patterns and templates describe language shape beside their consumers.
Native meta reuses the ordinary compiler/backend through project helpers;
compiler-owned native operations and matching linked wrappers own live
compiler queries. Runtime
Lisp is a separate evaluator and macro interface, with its own embedding and
closure lifetimes. It is not an alternative native-meta execution tier.

Var ledgers own native tag/conversion facts. List and String canonical identity
belongs to Pool; mutable collection identity/storage belongs to Scope/Block.
Typed Lists are views, while typed Arrays/Maps have native storage policies.
Context coordinates these lifetimes and graph export. Match prepares one
program/layout and uses invocation leases; Job owns child reaping and native
capture files. These boundaries are purposeful. Beautification should remove
surviving duplicate algorithms and finish owners rather than flatten all these
objects into a new framework.

## Ranked next packets

Evidence below is from clean exact-SHA source, separately from the locally
modified mitigation candidate. Proposed snippets are designs or bounded
temporary prototypes; passing a prototype does not certify production
integration. Detailed per-file evidence is retained in the workspace review
notes. Compatible repair and source cleanup can be commissioned independently
of unresolved public or representation choices.

| Rank | Packet / source owner | Class and evidence | Expected simplification / boundary |
| --- | --- | --- | --- |
| 1 | Match cached invocation, lib/match.x | Resource repair; a legal raising Var.equal strands a lease, blocks dispose and leaks the cache; deferred wrapper succeeds | One acquisition-local release, delete six normal-tail releases; preserve cache admission, pins, generations and callback/output semantics |
| 2 | Job capture release, lib/process.x | Resource repair; scope release reaps child but leaves two native FILE descriptors; explicit cleanup adds none | Detach each capture at consumption, close remaining owned captures in finalizer; retain explicit result-materialization and reaping policy |
| 3 | Typed Map result and JSON escape scratch, lib/map-generics.xmacro and lib/json.x | Lifetime repair; failed warmed conversion retains 5 allocations/144 bytes; five malformed escaped root strings retain 25/645 | Reuse existing complete-result guard and lexical scratch cleanup; preserve fresh Map identity, conversion order and JSON diagnostics |
| 4 | Compiler SymbolSet construction and region traversal | Compiler whole-operation repairs; extracted graph/encoding and queue kernel proofs preserve output/order | Bound seed-graph lifetime to one trial, consume final table after encoding; traverse List once using existing queue instead of repeated linked indexing |
| 5 | Macro persistence/application and helper-result rewriting, src/macros.x | Source-derived cleanup; persistence root/cutpoint/order proof is bounded, helper result still needs effect/identity controls | Reuse current AST child owner; delete two builders/two changed flags (about 12 lines); preserve naming versus application phase and exact template postorder |
| 6 | Main-entry and declarator expression | Compiler source candidates; backend/native-C compatibility decides adoption | Express complete generated operation through existing Function/template/rebuild owner where valid; retain fallback and C precedence rather than tighten grammar |
| 7 | Args repeated values, lib/args.x | Algorithm and private lifetime cleanup; 50/100/200 operands create 1225/4950/19900 extra canonical prefix cells | One private Array accumulator and one canonical final List; release spec/index/accumulators on all exits, retain public Map/List contract |
| 8 | Compile-time dedent, lib/system-macros.xmacro | Native-meta reuse plus public behavior repair; native String.dedent callable in six-case probe, physical CRLF differs today | Delete three duplicate dedent functions, retain literal eligibility/query owner; settle CRLF and regenerate linked meta through its authoritative owner |
| 9 | Wide numeric arithmetic, lib/varconvert.x and varops.x | Internal owner consolidation; long + ldouble boxes an unnecessary promotion before result | Reuse decoded-to-native target conversion, box only result; choose narrow internal interface and prove full family/rounding matrix |
| 10 | Flat template traversal, lib/match.x | Width repair; nonempty unused bindings at 500k siblings exhaust native stack; iterative prototype preserves seven finite canonical results | Iterate siblings with managed spine, recurse for genuine nesting; preserve current !quote behavior and separate positional void/presence policy |
| 11 | Unzip / Regex.split / Pool mutex initialization | Small connected deletions through existing owners; Unzip and Regex parity/allocation probes; mutex proposal source-only | Delete discarded prefix result, full find_all intermediate, duplicate native recursive-mutex constructor; retain complete native/error policy |
| 12 | Quasiquote and literate capture | Public/companion semantics; bare middle unquote atom incorrectly acts as suffix head; companion capture still uses spelling | Separate whole quoted form from element sequence; align companion with settled production capture/global-rebinding contract, preserving its own execution model |
| 13 | Compiler state, rendering and allocation construction | Bounded architectural investigations, not approved redesign | Preserve distinct identity/transaction/overlay owners until a complete candidate proves deletion; audit partial constructor rollback and format cost/contract separately |

[The checked-in coverage companion](compiler-library-review-coverage.md)
records all 111 files, their reviewed operations and explicit gaps. Consequential
focused evidence and complete current/proposed snippets are recorded below.
Full local logs and probe versions remain preserved in the isolated worktree.

The implementation candidates below are not all ready on the same evidence.
The named focused checks are finite integration checks for each packet,
not additions to a recurring readiness sequence.

## Concrete operations and caller effects

### Invocation release belongs beside acquisition

Current cached operations acquire, invoke user-controlled comparison, then
release normally. A caught transfer skips that tail:

```x2c
$match.lease(lease, status, cache, pattern, owner);
if (status == MACHINE_PREPARED) result = plan.try_match(input, out_bindings);
lease.release();
```

Put `defer $lease.release();` in the existing acquisition macro after acquire
returns, and delete the six tail releases. Inactive pressure leases remain
safe no-ops. Public direct acquire callers retain their existing release
obligation. Partial construction failures inside acquire need a separate
producer proof; this packet does not claim to fix every cache allocation path.

### A consumed capture relinquishes its field before fallible work

Current Job stores both FILE fields until both reads finish, then nulls them:

```x2c
job.output_text = _captured(job.output_file, job.nul_output);
job.errors_text = _captured(job.errors_file, job.nul_errors);
job.output_file = job.errors_file = NULL;
```

The proposed consuming operation takes `File &file`, moves it into a local
`owned`, then sets `file = NULL` before reading/closing it. The finalizer
terminates/reaps as today and raw-closes only fields still owned by Job. It
remains allocation-free and cannot raise; it must not materialize results or
depend on stage storage that may already have been reclaimed. Delete the
blanket late-null assignment. Aliases of an owned capture expire at release;
do not close borrowed stdio or introduce finalizer-driven Thread.join.

### Fresh conversion results are committed once

Current typed Map conversion allocates `packed`, fills it and returns it. A
conversion transfer leaves the unavailable partial result live. The Array
family already demonstrates the suitable producer contract:

```x2c
$map packed = NULL, result = NULL;
packed = packed._core_new_capacity(2);
defer if ((void *) result == 0) packed._core_free();
unsigned cursor = 0;
Var key, val;
while (entries.try_next(cursor, key, val)) packed.set(key, val);
return result = packed;
```

Successful empty Maps must remain fresh identities, so presence is not truth.
Boxing uses the same complete-result guard. The guarded temporary prototype
retains zero allocations on the demonstrated failure and preserves independent
successful Maps. Constructor rollback before this guard is a separate owner.

JSON's optional `Buffer decoded` instead needs `defer decoded.free();` beside
its declaration and ordinary String conversion while the Buffer lives. Delete
the success-only `str_free()` consumption. This manages scratch, not the
returned value, and does not create transactional Array/Map parsing.

### Repeated options construct one final immutable value

Current Args does this per occurrence:

```x2c
List earlier = option.given ? result[option.name] : NULL;
result[option.name] = earlier.append(%($value));
```

Proposed private `_Option.collected` appends each value to one Array, then
publishes `result[option.name] = option.collected.list_free()` once. A single
spec cleanup releases unfinished Arrays/index/options on all exits; Args.usage
uses that owner too. Preserve occurrence order, default replacement, empty
defaults, flag counts, required-row ordering, diagnostics and canonical result
identity. Public callers still receive immutable Lists of Strings and own
their later numeric conversion. No elapsed-time improvement is yet measured.

### Native meta consumes the ordinary String owner

Current `$dedent` implements width, blank-line and application algorithms in
three meta functions. Proposed literal folding keeps its exact source-spelling
eligibility and calls:

```x2c
String body = source.getslice(open, length - 1, 1);
return x2c_literal_string(body.dedent());
```

`String.dedent` is already `meta native`; a pure native-meta control matches
runtime results for LF/CRLF/plain/blank/empty/tab cases. Current physical CRLF
literal folding retains opening CRLF/indentation while runtime drops it.
Recommend the documented runtime result, explicitly changing that corner case.
Callers depending on the old literal result would need adjustment.

The complete change must edit the authoritative macro, run
tools/gen-linked-meta.sh and rebuild the compiler through the ordinary build
owner. Compiler-linked copies authenticate definition/callee hashes; an edited
standalone copy cannot borrow the stale linked query wrapper. Its failed copy
prototype establishes that boundary, not that ordinary native reuse is
impossible. Do not grant project helpers live compiler queries or add another
execution tier. Owner-generated integration has not been prototyped yet.

### Delete results nobody consumes

Unzip currently calls `remslice(0, consumed)` then frees the removed Array.
Use `setslice(0, consumed, NULL)` instead: same original buffer identity and
remaining order, zero versus two allocation/free calls at the tested threshold.
The probe covers the buffer-cut kernel, not a fully rewritten Unzip.
Interleaved-source/lagging-column and existing600-value controls remain
integration checks; the proposal changes no source-pull or cursor obligation.

Regex.split can iterate its existing `_search`/`_next` traversal directly
instead of `find_all`. Six temporary corpus cases retain canonical output;
200 captured commas avoid 200 temporary List cells and one growing collection.
This retains capture construction, offsets and empty-match progress.

Pool can call the existing allocation-free
`x2c_mutex_recursive_initialize(&pool.mutex, message)` and delete its duplicate
pthread-attribute initializer. Preserve fatal message, recursion, attr cleanup
and lock order; the ordinary throwing Mutex constructor is a different owner.

### The compiler consumes its own collection and lifetime operations

Current region scanning in src/regions.x repeatedly indexes a linked List:

```x2c
for (int i = children.len() - 1; i >= 0; i--)
  w.pending.push(children[i]);
```

Append children once with foreach, then reverse only the appended suffix of
`w.pending`. Keep the existing prefix and LIFO order. Root reproduced parity
for 0/1/2/31/2000/20000 children and a proposed 500k completion. The 20k kernel
measured about 0.154 seconds versus 0.000161 seconds locally; this is not an
integrated compiler timing or performance forecast. One linear collection
operation replaces repeated linked traversal without another state owner.

SymbolSet's src/literals.x `_try_seed` constructs seven Scope arrays per
trial. Give the entire graph/peel/assign operation a trial-local `$scope()`;
its external table is borrowed and survives the trial, while the graph does
not escape. Failed span tables and successful encoding scratch need their
own complete consumption boundaries. Preserve seed order, span selection,
encoded bytes and canonical output; skip no failed trials as an algorithm
change. Root reproduced the exact extracted algorithm for two distinct Symbols: all 4096
first-span trials fail; complete hashing/encoding retains 28,681 Scope allocations
and 319,638 requested bytes. The bounded version retains 0/0, with identical
canonical encoded Strings for two and three Symbols and the same 28,686
allocation calls. This is operation-lifetime improvement, not an allocation-call
reduction or a rebuilt compiler-memory benchmark.

The zero-retention SymbolSet proof covers all three owners together:

```x2c
// Trial: symbols and output table are borrowed from the parent.
static int _try_seed(
  Array symbols, uint32_t span, uint64_t seed, uint32_t *table) {
  $scope() {
    SymbolSetGraph g = _graph(symbols, span, seed);
    if (!g.peel()) return 0;
    g.assign(table);
    return 1;
  }
}
// Failed span, after the unchanged seed loop:
if (!built) {
  Scope.free(h.table);
  h.span <<= 1;
}
// Successful hash/encoding/AST construction stays together:
static List _set_expression(Array symbols) {
  $scope() {
    String text = _encode(symbols, _hash(symbols));
    List bytes = %(expr (* char) (literal (* char) $text));
    List decl = %(decl ("SymbolSet") (bindings (bind () ())));
    return %(expr ("SymbolSet") (cast $decl $bytes));
  }
}
```

The canonical String/AST survive in their existing Pool. Scoping only the
trial would leave failed span tables and the final encoding scratch live.

### Function-body replacement and declarator folding retain their owners

Current `generate.x:_patch_main` manually copies the return type and complete
binding/declarator while prepending the initialization call:

```x2c
return %(function $type (bind $binding $params)
  (block (stmnt INITIALIZATION_CALL) @body));
```

Proposed replacement uses the existing `_replace_initializer_body`, whose
Function decorator delegates to `Compiler.rebuild_function`:

```x2c
return _replace_initializer_body(c, node, setup.append(body));
```

Keep the exact existing typed initialization call in `setup`, match only
`main`, and retain one call before the original body. The existing rebuild
owner retains syntax, return type and declarator without rebinding lowered
children. Delete the second function reconstruction, adding no helper.
This is source-contract proof only: generated AST/C/origin parity, ordinary
and argument-bearing main, file-init and conditional-init controls remain.
No public caller change is proposed.

Current declarator dispatch selects `fnmod`, then its helper rereads
`func.cadr()`. A proposed dispatcher captures the consumed child and tail:

```x2c
case %((fnmod ?parameters *) *remaining):
  return e._function_declarator(decl, parameters, remaining);
```

The helper emits `parameters` instead of `func.cadr()`. This case alone does
not replace the family. Keep omitted parameter fields as NULL, arbitrary
fnmod tails, nested array-head recognition, text attributes, unfamiliar List
bitfield fallback, scalar Var-to-Symbol conversion, whole-tail scalar bitfield
emission, typedef/pointer prefixes and `^` passthrough. Parentheses inspect
the already folded declarator at the current step. The complete compatibility
table is in the parser/backend packet. Replacing five isolated selectors
without whole-family C precedence/constructed-syntax/deep-stack parity does
not establish a simpler owner. No new validator or accepted-grammar reduction
is proposed; exact production integration remains conditional.

### Derived compiler metadata stays local to its operation

Source-only secondary candidates reuse existing producers:

- `_signature` currently allocates an Array, repeats the resolved-entry type
  loop and manufactures `(void)` for no parameters. Delegate to
  `compiler.lambda_param_types(entries)` and cache the existing signature.
  Delete the duplicate loop/empty Array, about four net lines. Retain the
  capture reader's distinct empty argument list. Its producer contract must
  account for unsupported rows: one owner skips them, the other pushes NULL.
- `NativeResolution.rows` copies and substitutes the same native bindings
  for each member. Create that Map lazily once after the first successful
  requirement; use `expected` directly for exact representation. Delete m-1
  copies for m non-exact members, or all m copies for exact representation.
  Source grows roughly one line; actual counts and signatures are unmeasured.
- `_lower_return` derives unwind cleanup twice along the same saved-value
  path. Derive it once and compose through the current return operation.
  Preserve value materialization before innermost-first cleanup, ordinary
  transfer semantics and the existing nested block shape initially. Any block
  normalization is a separate representation choice.
- `_init_call` reverse-conses constructor arguments and repeatedly measures
  the List. A forward Array can consume the same object/argument order.
  Measure actual constructor sizes before claiming a useful improvement;
  malformed-row/diagnostic order remains a boundary.

Definition-source rendering in `generate.x:_source_text` is a lower-priority
source-only candidate: replace `parts.push(token.text)` followed by
`"".join(parts.list_free())` with one managed Buffer scan writing the same gap
and token bytes. Delete the intermediate Array/List of text pieces. Exact
`--dump-definitions` bytes and allocation/cost parity are unexecuted; do not
call this a measured improvement.

Exact complete current/proposed operations and existing controls are in the
semantic packet. Current signature-alias/foreach controls pass; they do not
validate these unimplemented proposals. No persistent memo, new parameter
representation, substitution cache or return protocol is justified.

### Macro persistence and application share structural mechanics

Current `_macro_value_names` and `_macro_value_bindings` each construct a
managed Array and maintain a changed flag for the same fallback walk. Keep
naming's binding-identity replacement and application's binding-name resolution
and opaque tpl-call case, then use the already imported language macro:

```x2c
List child;
$ast.rewrite_children(value.list(), child, _macro_value_names(child));
```

Application uses `_macro_value_bindings(c, child)` in the same existing owner.
Atoms remain unchanged, children visit left to right, and unchanged roots retain
identity as they do today. About 12 authored fallback lines/two builders/two
changed flags disappear without another helper. Actual Macro persistence across
scopes, hygiene, source identity and pending-template fixtures remain required.

`_helper_result` is a related conditional rewrite, with a distinct postorder:
resolve stored before values, then compute invocation site/open SDK frames.
Every finite canonical List input currently returns a List, so child resolution
cannot change marker length/atomic label/third-field List eligibility. That
supports a pre-match design, but effectful nested controls, diagnostics and
canonical-pool identity still need execution. Do not blindly place a marker
match after a macro that returns from the enclosing function. `_open_natives`
and capture cardinality/forward vocabulary remain separately bounded adopters.
No new role record, AST validator or macro execution tier is proposed.

The literate companion must also describe the settled capture caller effect:
conservative capture can retain local values/referents longer; borrowed
referents must outlive the closure. Globals remain lookup-time names and can
be rebound. Correct its stale wordcode/equivalence claim and document its
separate recursive execution/embedding limitations with the companion change.

### Numeric and template operations remove intermediates, not policy

Current wide floating arithmetic converts each operand to a boxed Var and
then reads the native value again. The proposed shared conversion consumes
already decoded `X2CVarNumeric` values and boxes only the result:

```x2c
// Current ldouble branch, after boxed lhs/rhs promotion:
long double a = left.long_double_value(), b = right.long_double_value();
return Var.box_long_double(_ldouble_step(op, a, b));
// Proposed narrow internal owner, shared with Var.convert:
long double a = x2c_numeric_ldouble(lhs), b = x2c_numeric_ldouble(rhs);
return Var.box_long_double(_ldouble_step(op, a, b));
```

Long 2 plus ldouble 0.5 keeps tag/value 2.5 and uses one rather than two
allocations in the bounded native prototype. Expose three existing native
converters through the smallest internal interface, without duplicating their
formulas or using long double as a universal intermediate. Direct target casts,
public exact-tag identity, fresh wide-result lifetime and error causes stay.
The fifteen-family/rounding/NaN/boundary matrix and native-meta reach remain.

Current template `_replace` recursively visits both each head and its cdr:

```x2c
head = _replace(head, bindings);
tail = _replace(tail, bindings);
return %($head @tail);
```

The compiled prototype walks siblings once, stores `(head, splice)` steps in
an operation-owned Block, and builds the canonical result backwards. Only
actual nested elements recurse. Seven finite cases preserve canonical identity;
500k siblings complete with zero retained scratch. Delete flat-tail recursion,
with a small source increase. Preserve current tail-headed `!quote` behavior
and positional void/presence policy; changing either is separate semantics.
The exact complete prototype and root/binder/splice controls are in the library
packet. Production integration and the sibling `_is_list_literal` proof remain.

Quasiquote needs a different, explicitly semantic repair. Current `_qq`
passes `form.cdr()` back as a whole quoted form; a middle bare `unquote` atom
then becomes a suffix head. The observed `` `(a unquote (+ 1 2)) `` returns
`(a)` instead of three ordinary quoted elements. Proposed ordinary-form
handling passes the whole sequence to one `_qq_elements` operation:

```x2c
if (head != lsym_unquote && head != lsym_splicing)
  return _qq_elements(lisp, form, env, depth);
```

That owner iterates elements, applies `_qq` to actual nested forms, and uses
the existing splice arity/type owner. Preserve lexical environment, effects,
active depth and malformed-form diagnostics. Caller-visible corner cases
change, so commission this separately from template width cleanup. No compiled
production candidate or complete nested/splice/width matrix is claimed.

## Parallel execution when commissioned

Compatible ownership repairs form the first batch: Match, Job, typed Map and
JSON have disjoint file owners and can proceed independently. Args and small
collection/traversal deletions can run beside compiler source-expression work.
Root integrates and reviews connected changes, especially Match lease/template
work sharing one file. Generated sources stay under their existing owners.

Native dedent waits for its stated behavior choice and owner-generated proof.
Numeric conversion waits for the internal interface and full target-cast
matrix. Quasiquote changes and any compiler state/cache/transaction change are
separate semantic/representation packets. Beautification authorization alone
does not settle them. The already settled stopping, conservative capture,
single-tape and libuv choices are not reopened.

Use relevant existing suites/examples/fixtures for each operation. Preserve
expectations and current readiness targets. No new recurring gate, planning
step, benchmark requirement or precommit expansion is proposed. Before any
later authorized delivery, report branch/dev ancestry, complete diff,
validation and remaining work; push only to an explicitly authorized
destination. Main and local dev remain outside this campaign.

## Reconciliation and effect on size/readability

Dev's dual-macro and native-meta campaigns already removed competing syntax
and execution owners. Current `_capture_layout` consolidation is present;
repeat no old prerequisite campaign. Existing typed collection kernels are
real; the larger unpublished source-consolidation prototypes are distinct
research, not delivered deletion counts. Wave 0-5 beautification improved
navigation but grew source and distributed operations over more helpers.
The next pass judges whole-operation reading paths and actual ownership.

The completed local mitigation adds 41 net compiler lines and 31 net library
lines while deleting duplicated traversals, match-result recovery and manual
cleanup. Deadline/capture/width correctness explains growth. Optional package
implementation is 22 net lines smaller, separately from its report example.
Tests, book text, generated links and plans are counted separately in the
complete diff. These are actual candidate counts, not a forecast for this pass.

The next plan has real deletions, but allocation/width repairs can add source.
No total LOC reduction is established before complete implementation and
interface glue are counted. Retain direct loops where state/order makes them
clearer. Reject helper extraction that scatters a complete operation without
removing a duplicate fact or representation.

## Coverage and limits

All 111 direct src/lib .x/.xmacro files are accounted for exactly once:
40 compiler files and 71 library files, with no missing or duplicate assignment.
This comprises 110 authored files and generated src/linked-meta.x; generated
lib/x2c.x is separately retained under its Makefile owner. Compiler coverage
is 19 driver/meta files by complete-operation review (not uniform every-line
proof), seven semantic and fourteen parser/backend files by full body reads.
Library coverage is 43 values/Lisp/Match and 28 lifetime/IO/thread files by
body/operation review with per-file ledgers. Their totals are 47,780 compiler
and 33,358 library source lines; line totals are inventory, not execution.

Independent first-impression notes preceded each partition's dev plans/history
reconciliation. The original seven requested areas are compared with actual
coverage in the completion audit: compiler/meta, Lisp/macros, runtime, build/
tooling, packages, tests/examples and documentation. Focused clean-baseline
probes establish only the named boundaries, not every path of unimplemented
snippets. The authorized mitigation's combined checks validate that candidate,
not proposed next-pass rewrites.

No full arithmetic matrix, allocator/fork/EINTR failure campaign, sanitizer or
race proof, alternate-host/device/backend campaign, complete native-handle
proof or performance certification is claimed. Current Thread/Context/Pool
identity and compiler snapshot/carry/transaction differences remain explicit.
Positive libuv directory delivery remains unverified: raw native start works
but callback reports EMFILE; repaired propagation is separately tested.

The accompanying mitigation PR is authorized for dev; larger pass delivery
remains separately scoped. Preserve the isolated worktrees, generated
artifacts, complete logs and probe evidence. This plan adds no source edits to
the larger beautification pass.
