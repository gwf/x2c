# Critical review evidence and finding dispositions

> Status: reference, 2026-10-11.
> Baseline: fetched `origin/dev` `6529e8689702d98db2754571ef7f3d9b43b0d5b9`.
> Final delta checked at `9004c40b63ad489625d1a19371124f4b4f32978a`.
> Supports [the remediation plan](../review-remediation-2026-10-11.md).
> Source defects, observed behavior, and proposed policy are distinct below.

## Reference disposition, 2026-10-24

Retained as dated evidence, not a current defect or task list. The move
preserves the original observations; no historical probe was rerun.
Use the active [writing plan](../review-remediation-2026-10-11.md) and
[review follow-ups](review-followups-2026-10-24.md) for remaining scope.
The language ledger accounts for 181 historical study rows, not 181 tasks.


## Evidence standard

`Executed` means the coordinating reviewer ran the stated behavior in this
checkout or an isolated copy of the same revision. `Source` identifies an
inspected implementation or documentation fact. `Prior only` means supplied
evidence was read but the claimed outcome was not independently reproduced.
Neither a generated-C comparison nor a successful translation implies a
successful native build. An observed result does not settle intended semantics.

Local raw evidence is in `.context/critical-review/` and `debug/critical-*`.
The small reproductions below and exact source owners make the conclusions
usable without the original temporary review directory.

## Final-tip supersessions

The fetched tip advanced by nine commits during the review. A fresh physical
copy of `9004c40b` passed `make build-safe`; targeted executions used its own
compiler and home. The original tables below preserve baseline evidence.

| Baseline item | Final-tip state |
| --- | --- |
| 10: for-initializer cell | Fixed by `eff08cee`. The new fixture runs with `2`, `12 99`, `4 5`; no repair remains in A for this path. |
| N2 / D15: module trivia | Fixed by `28fc8c97`. New fixture prints 42 and original commented opener succeeds. |
| N3 / D17: conditional reads | Partly superseded. Known unreachable arms are hidden before discovery. Missing member under `#if 0` succeeds; under `#define DISABLED 0` / `#if DISABLED` it still reports cannot read member. This is shared limited classification, not full native preprocessing. |
| Script member discovery | Upstream now removes module members from standalone script helpers. Source delta reviewed; do not propose that already-landed repair. Payload copying and linked-meta discovery remain separate. |
| 1, 2, L3 | Current-tip executions still reproduce wrong match/catch bindings, signed percent-literal mismatch, and two escaped dollars collapsing to one. The datum-reader repair is a different owner. |
| Other findings | Their relevant authored owners are unchanged by the inspected delta, apart from surrounding CLI probe additions. Baseline evidence remains relevant; no claim that every probe or a full gate was rerun. |

Current-tip raw results are in `.context/critical-review/latest-replay/`.
The original checkout and its compiler remain at the initial baseline; the
newer compiler was built in the disposable copy recorded by `latest-copy.txt`.

## Ranked findings

| Input ID | Disposition and consequence | Current evidence and owner | Remediation |
| --- | --- | --- | --- |
| 1 | Confirmed silent wrong binding; headline diagnosis corrected | Executed: match binder stays 5, lambda reads/writes global to 101. Macro match/catch sees caller argument as 5 instead of 77. `src/compiler.x:2582-2598`, `src/symbols.x:290-294,344-360,539-556`, `src/lambdas.x:447-456`, `src/component-match.x:275-285`. `Sym.define` DOES issue an identity; ordinary declaration facts and identity transport are missing. | A: ordinary binding and template-local handling, carried through lowering. Catch hygiene is separate from match capture facts. |
| 2 | Confirmed signed percent-literal decoding defect | Executed: small negative is tagged long while positive is i32; runtime int -5 misses the pattern. `lib/type.x:494-511,559-570`, `src/literals.x:961`. Sign reaches digit decoder. | C: shared signed-token decoding; signed-minimum boundary evidence. |
| 3 | Confirmed undefined local read; reported crash is not reliably reproduced | Source plus Clang `-Wsometimes-uninitialized`: `src/macros.x:3681-3688`. Parent mixed-object `-O0` run translated the named fixture successfully three times, then three times with a matching refreshed prelude. Supplied review's SIGSEGV remains prior evidence. Success does not initialize `direct`. | B: use existing absent-value sentinel or branch returns. Do not promise every `-O0` build crashes. |
| 4 | Confirmed warning-policy scope, not 321 distinct defects | Executed `cc -fsyntax-only -Wall` across fresh generated lib/src: 321 warnings, including 17 sometimes-uninitialized diagnostics at two source sites. 181 unused functions, 98 unused variables, 24 set-but-unused, one missing-braces. `builds/stage.mk:41-46`, `etc/build-config.mk:53`. | Correct wording now; additional recurring warning flags require policy approval/cost accounting. Trace emitter invariant before repairing its warning. |
| 5 | Confirmed false-success build and wrong mode in a path containing a space | Executed isolated archive: `make build-safe` and `make stage-1` both exit 0; stage compiler absent; `config-show` reports debug although tracked mode is optimize. Bootstrap native work did run: "builds nothing" overstates the whole command. `builds/stage.mk:7-12`, `etc/build-config.mk:10-16`. | D: truthful failure and mode lookup; do not infer arbitrary-path support from one quote fix. |
| 6 | Confirmed expression rewrite visibility; intended rule unresolved | Executed interpolation rewrite intercepts `String.join`. `src/component-interpolation.x:29`, `src/macros.x:2733-2736`; statements/functions have filtering. Existing docs do not promise identical expression filtering. | G: decide and state visibility by rewrite boundary, retaining source subexpressions and canonical construction. No origin authentication. |
| 7 | Confirmed deliberate tag-sensitive order/equality | Executed Array length tag ulong differs from int 3; 1 compares above 1L; Map key families differ. `lib/dispatch.x:512-521`, `docs/src/library/modules/var.md:368-370`. List length is int: do not generalize all lengths. | Document operators and Map consistency; semantic change requires decision. |
| 8 | Confirmed false-pass assertions | Executed Bash 5 and 3.2 compound-list counterexamples. Five lines at `unittest/probes/run-cli-boundary.sh:1860,1861,1896,1911,1915` skip failure on wrong status. | D: explicit failure branches, with wrong-status fault injection. |
| 9 | Confirmed invalid generated lvalue operation; coverage count corrected | Executed native syntax check rejects address of register and warns about const discard in `var-native-lvalue-boundaries.c:40-41`. Exactly 58 phase files contain c/h and no native/run phase under the stated predicate. That count does not mean all 58 are invalid. | B fixes semantic boundary and this fixture; broader native coverage remains policy proposal. |
| 10 | Confirmed at baseline; fixed at final tip as above | Executed for-initializer `using &x` fails with unbound `?__lambda_cell_0`. `src/component-lambdas.x:136-219`; initializer is a distinct canonical position. | No remaining repair: preserve the landed loop-scope change and fixture. |
| 11 | Confirmed docs-only coverage boundary | Executed physical archive copy: changed idioms output 5 6 to 5 7; `doc-generate` and `doc-check` exit 0, `doc-outputs` exits 2 and names that sample. An initial symlinked-build experiment failed due to prelude/source-root mismatch and is not the supporting result. `Makefile:319-330`. | D policy proposal; no automatic new recurring doc gate. |
| 12 | Confirmed current continuation and owner drift | Source: implementation map routes match/update to former owners; foundation opening/resume instructions disagree with delivered log; String-switch plan names absent `x2c_literal_int` and changed `add_support` visibility. `src/compiler.x:2344-2351`. The rewrite fixture is an example, not a shipped ordinary String-switch feature. | F: reconcile current status and APIs, preserve accepted feature semantics and dated history. |
| 13 | Confirmed wide index aliases valid element; public boundary needs care | Executed 4294967297L reads second List/Array/String element and writes Array element 1. Int-taking APIs narrow before bounds handling. `lib/list.x:471`, `lib/string.x:639`, component access and slice helpers. Native C arrays are a different contract. | C: preserve documented out-of-range behavior through one checked conversion/wider boundary; assess public signatures. |

## New findings in the supplied update

| Input ID | Disposition and evidence | Remediation |
| --- | --- | --- |
| N1 | Executed `make -o build proof-raw-symbols`: 933 required, 487 excluded, 928 compared, five failures of 1420 sources. The five are module-block, dump, meta, nested, statics; CPP=1/raw=0. `src/frontend.x:77-83` deliberately rejects module CPP mode; sweep lacks corresponding classification. | E: repair optional proof classification, preserving receipts. No new gate. |
| N2 | Fixed at final tip; baseline execution: comment before module brace fails. A separate `module {` spelling in unrelated text can enable the lexical pass and make it succeed. `src/collect.x:342-351,378-390`. | No remaining prefilter repair: preserve the landed lexical owner. Remove the obsolete comment restriction from the draft. |
| N3 | Baseline source and execution support entry-mode parsing and eager reads; final-tip known-unreachable suppression supersedes the unconditional-read claim. The claim that #if is ignored is too broad: spliced text remains conditionally compiled. Duplicate entries duplicate text, consistent with ordered splicing. | F/G: specify reading, tokenization, and conditional compilation separately. No duplicate validator by default. |
| N4 | Executed UBSan with only collect.c instrumented: applying zero offset to null pointer at generated collect.c:1680. Source `Splice.own`, `src/collect.x:437-438`. Stock empty member succeeds. | E: handle empty range before pointer arithmetic. |
| N5 | Source and generated header: alias constructor emits `Values_new()`. `src/compiler.x:1170-1190` versus ordinary empty-parameter producer. | B: reuse canonical void parameter representation; focused strict-prototype check. No new warning gate required. |
| N6 | Source-supported adoption prerequisite, not present shipped failure. Payload copies flat basenames; linked-meta script scans top-level lib/src. No shipped source currently adopts module blocks. | E: member-closure payload/meta discovery before self-hosted adoption. Avoid treating members as units. |
| N7 | Source: module-block-included declares symbols/c phases only. Does not prove native header consumer behavior. | E: focused consumer/provider native proof; recurring-phase expansion requires policy decision. |
| N8 | Source: completed module plan remains active-location with branch status; index lacks it. Prelude proof exclusion is repeated in two tools. Duplication alone is not a defect. | F: correct status/archive/index with landing evidence; consolidate classification only where it removes real duplicated ownership. |

## Lower-value and dropped claims

| Input claim | Disposition | Action |
| --- | --- | --- |
| Make 4 retry regex | Executed representative error lines: `[stage-diff-0] Error` matches, `[Makefile:6: stage-diff-0] Error` does not. Source `tools/land-dev:166`. | D: recognize both exact target formats; preserve other failure rejection. |
| Retained integrator branches/refs | Source has creation and no cleanup. Historical counts are workspace-dependent and not severity evidence. No audit of recoverable work performed. | Optional explicit cleanup investigation, not automatic deletion or a new recurring cleanup policy. |
| Lisp int overflow | Executed small int expressions wrap on this host. Supplied C comparison used long operands and was not like-for-like. No diagnostic obligation established. | Document/decide numeric semantics; do not classify absence of Clang warning inside Lisp as compiler bug. |
| Region warning probe ignores failure | Executed extracted pipeline with producer status 134 still passes. `run-header-cache.sh:149` masks producer status. | D: collect status before filtering. |
| Graph empty parity | Executed two failed producers through successful filters compare empty output successfully. `commands/graph/tests/run.sh:22-33`. Other graph assertions may still catch wider failures. | D: check each producer, then compare. |
| llms final newline/CRLF | Executed removed final newline passes `--check`. Source uses `Diff.unified` as equality. CRLF was not independently mutated. | D: byte equality; diff for explanation only. |
| Renamed docs heading | Executed renamed Partial contracts heading passes audit. `tools/check-docs:334-346`. | D: require delimiters before existing section check. |
| Bash 3.2 and Python optimization | Executed bare `[[ false ]]` continues on stock Bash 3.2, stops on Bash 5; `python3 -O` removes an assertion. Exact repository-wide vulnerable-line counts were not independently recounted. | D: explicit failure semantics/entry contract, not silent bypass. |
| var-chain-stack at O0 | Prior only for exact failure; source limit is 256 KiB and intended optimized workload matters. Small frame headroom is not proof of a shipped failure. | State workload/build mode; measure before changing threshold or compiler architecture. |
| Stale meta-helper status sidecar | Source: phases stdout/status; compile-status file remains 1 and is undeclared. | D: remove obsolete sidecar within later authorized cleanup. |
| Calling a Var | Executed native compilation rejects a boxed Func called through Var. Dynamic boxed callability is not promised. | Optional ordinary callable diagnostic improvement; no new dynamic call feature. |
| Negative wide Lisp C constants | Prior only for specific generated cast; supported-host result does not establish portable semantics. | Include in platform/number boundary review; no speculative portability rewrite. |
| Installed component-lambdas includes absent ast-rewrite | Executed a scratch installed-home lambda capture: prints 5 while ast-rewrite is absent from the payload. Missing include alone is not evidence of broken installed operation. | Do not expand the payload from this inference. Module-member adoption has separate concrete requirements. |
| Hand-kept component lists/head vocabulary | Distinct consumer inventories may be legitimate. No universal registry justified just by multiple lists. | Consolidate only demonstrated shared ownership; couple module adoption with its actual consumers. |
| Fleet worker hook | An uncontexted checkout is treated as individual by current tool design. `agent_context.py:38-43`; documented worker setup is orchestrator responsibility. No provider-specific defect established. | Apply existing worker/private context at launch; do not add provider-name detection. |
| Driver absorbed kernel deletions | Already acknowledged in foundation decision log; supplied numerical complaint partly corrected by its own verifier. | No new requirement. Preserve accepted accounting when measuring future changes. |
| Forged try/function kernel marks | Supplied verifier rejects them; parent independently replays source-function marked/control probes. Bound/lowered carrier contracts are a separate untested route. | Do not advertise marked raw forms as public syntax or add origin validation. |
| Missing include diagnostic | Translation can defer host includes to native compilation; build failure is expected boundary. | No new early validator without a concrete unmet language contract. |
| preprocess-missing-include status-only fixture | Host-dependent diagnostic text is a plausible deliberate scope. No reproduced false positive specific to this fixture. | Retain unless an actual regression needs stronger stable evidence. |

## Additional findings and closed coverage gaps

| Area | Independent evidence | Consequence |
| --- | --- | --- |
| Acquired-value cleanup | Executed `$auto` acquires Item 1, user binding changes to Item 2, cleanup prints `clean 2`. `src/builtins.x:29-35` schedules the binding's later value. | Contradicts the standing acquired-value requirement. Batch B retains the acquired value once. |
| Escaped percent-string dollars | Executed two escaped dollars produce length 1 and `$`. `src/literals.x:887-890` unescapes before collapsing `$$`. | Batch C repairs decoding after stating the escape contract; generated data agreement is not independent proof. |
| sizeof operand parsing | x2c rejects `sizeof (xs)[0]`; an independent native C control compiles and prints 4 for the int element. `src/expressions.x:407-426` returns before operand postfix continuation. | Batch C restores ordinary operand parsing through its existing owner, preserving type-name and VLA boundaries. |
| Package imports | Built beta and alpha archives, where alpha imports beta. Consumer importing alpha prints 8. An included source importing beta links with its consumer and prints 7. | Close these two unexecuted workflow questions for the tested paths. Alias collisions and cycles are not thereby proved. |
| Installed `.xp` package | A fresh scratch home installs `indentpkg/src/indentpkg.xp` with status 0; consumer import fails as unknown and lists only `.x` search paths. `src/install.x:344-346`, `src/utils.x:265-266`. | Batch E aligns accepted install entries with import lookup. |
| Protocol documentation | Fresh private static-body probe works. `src/parse.x:313-320` carries privacy; `src/protocol.x:755-762` retains a protocol AST node. Guide lines 113 and 157 contradict these facts and its own line 138. | Batch F corrects the two sentences; no new parser or protocol representation. |
| Protocol behavior | Five runtime fixtures and three negative fixtures replayed; fresh associated-type ordering/inference and macro grouping probes checked. | Bounded support for the contract inventory, not exhaustive conformance. Grouping outputs 84, 6, 0 do not prove globally minimal parentheses. |
| Function declaration order | A module member function calls a later entry-defined static function without a prototype and prints 9. | Correct the book/plan's blanket C-order sentence. Private type ordering remains a distinct boundary. |
| Written function visibility | `lib/meta.x:183-188` still promises lifted lambda bodies reach program function rules, contrary to the newer guide, filtering implementation, and delivered foundation log. | Correct source API comments and regenerate their page, following the accepted design succession. |

The corresponding local records are `packages.json`, `xp-install.json`,
`parent-protocols/results.json`, `parent-final-probes/results.json`, and the
compiler/meta probe reports under `.context/critical-review/`. The package
record retains initial setup failures: `static-lib` was an incorrect CLI value,
and building an included-source consumer alone omitted its provider. Successful
evidence uses `--kind static-library` and includes both source units.

## Reproduction patterns

Use a freshly built compiler from this baseline. Compile each small source with
`builds/0/x2c run --build-dir /tmp/unique-output /tmp/probe.x`.
Do not reuse a build directory between different experimental compiler images.

### Match capture and macro hygiene

```x2c
Var n = 100;
Var global_n(void) { return n; }
int main(void) {
  match (%(go 5)) {
    case %(go ?n): {
      Func rd = %!() => n;
      Func wr = %!() using &n => n = n + 1;
      wr();
      printf("%s %s %s\n", n.repr(), rd().repr(), global_n().repr());
    }
  }
  return 0;
}
```

Observed: `5 101 101`. The lambda snapshot and reference write must use the
match binding, leaving the global unchanged. A separate macro with
`case %(?n)` and an `Expr $e` argument invoked with caller `n = 77` prints
`n=5 e=5`; ordinary foreach-local control preserves `e=77`.

### Wide indexing and cleanup ownership

```x2c
int main(void) {
  Array a = [10, 20, 30];
  long index = 4294967297L;
  a[index] = 99;
  printf("%s\n", a.repr());
  return 0;
}
```

Observed: `[ 10, 99, 30 ]`. The index must not silently select element 1
under a range-preserving collection contract.

```x2c
typedef struct Item { int id; } *Item;
void Item.cleanup(Item value) { printf("clean %d\n", value.id); }
protocol Cleanup(Item);
int main(void) {
  struct Item first = {1}, second = {2};
  { Item value = $auto(&first); value = &second; }
  return 0;
}
```

Observed: `clean 2`. Gary's standing acquired-value requirement is `clean 1`.

### Native and alternate-build checks

Native fixture check:

```sh
cc -fsyntax-only -iquote builds/0/lib \
  unittest/compiler-fixtures/var-native-lvalue-boundaries.c
```

Use `-iquote`, not `-I`, for generated runtime headers. `-I` can select x2c's
string header in place of the host C library header and invalidate the probe.

The empty-module UBSan experiment compiled `builds/0/src/collect.c` with
`-O1 -fsanitize=undefined -fno-sanitize-recover=undefined`, then linked that
object with the remaining stage-0 compiler objects and runtime archive.
`X2C_HOME` named the baseline checkout. Translating an entry with one empty
member reported null-pointer arithmetic. This isolates the source owner; it
does not claim whole-compiler sanitizer coverage.

The uninitialized-read experiment similarly replaced only the private
`macros.o` with `-O0`, preserving the shipped generated C. It did not edit or
replace the workspace compiler. Translation succeeded both with stale identity
fallback and with a matching prelude refreshed in a disposable physical copy.
The source and warning still establish a read before initialization.
