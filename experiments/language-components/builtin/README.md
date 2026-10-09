# Builtin collection access: measured candidate

> Historical measurements from `gwf/language-components`, through 945ac5ee.
> These are not measurements of the recovered foundation branch. See the
> [active plan](../../../plans/language-components-foundation.md) for current state.

Implementation: `fa68a538`, repaired at `bdcbfea1`, with prepared macro
matchers at `c1e06211`. The final compiler is converged.
Baseline: `a56da260`. Everything remains local on `gwf/language-components`.
No publication or advancement of `dev` or `main` occurred.

The candidate exercises the authoring mechanism in a real builtin. The
declaration-ownership repair below removes the added helper prototypes. It
also removes older redundant prototypes, so access C intentionally differs
from baseline. Total authored compiler size increases. Work remains local
and held for review. Earlier measurements below describe the pre-repair state.

## Authored component and retained kernel

[`src/component-access.x`](../../../src/component-access.x) selects Array/Map
stores, all ten compound operations, and prefix/postfix increment/decrement.
It uses ordinary `$rewrite` decorators, macro patterns, Code/Type methods,
and quoted calls. Its algorithms are linked into the compiler through the
existing shipped-meta mechanism. Included user components use the same
[`lib/rewrite.x`](../../../lib/rewrite.x) registration.

Generic getter admission, conversions, and custom-protocol evaluation order
remain with their existing compiler owners. Collection storage, tags, and
failure atomicity remain in the unchanged runtime helpers. The Type query
`protocol_member` delegates to the existing context-sensitive resolver; it
preserves explicit adoption and suppresses selection inside that member's
own implementation. Ordinary user rules retain their order before builtin
defaults.

The installed payload includes the builtin source for declaration replay.
The prelude source list also tells script builds which dependencies already
have linked implementations. Those sources still invalidate caches; scripts
do not compile them as extra runtime units.

## Compilation time

Each pair of quiet runs used seven alternating baseline/candidate pairs after
one warmup per compiler and workload. Both compilers were converged. Both
received the same absolute source paths and output directory. Translation
used `-j 1 --no-deps`; native C compilation was excluded. CPU seconds include
child processes. These are warm translation measurements, not full-build
measurements or instruction counts.

Initial candidate (`bdcbfea1`):

| Workload | Baseline elapsed, seconds | Candidate elapsed, seconds | Ratio |
| --- | ---: | ---: | ---: |
| Native, run 1 | 0.265704 | 0.285930 | 1.076 |
| Native, run 2 | 0.266528 | 0.286499 | 1.075 |
| Access, run 1 | 0.610473 | 0.988239 | 1.619 |
| Access, run 2 | 0.609952 | 0.989565 | 1.622 |

Native: 300 functions, 2,401 source lines, with native arithmetic and pointer
indexing. Access: 120 functions, 6,131 source lines, with 5,400 mutations and
240 reads. The access workload includes Array/Map aliases and a Map alias
whose getter returns String.

Median child-inclusive CPU seconds were 0.264649 -> 0.284912 and
0.265399 -> 0.285499 for native; 0.609244 -> 0.986629 and
0.608627 -> 0.987890 for access. The repeated measurements show approximately
7.5% native overhead and 62% access-heavy overhead for this implementation.
No runtime speedup or whole-build slowdown has been measured. Scaling across
many builtin components has not been measured.

Prepared matcher candidate (`c1e06211`), measured with the same workloads:

| Workload | Baseline elapsed, seconds | Candidate elapsed, seconds | Ratio |
| --- | ---: | ---: | ---: |
| Native, run 1 | 0.265908 | 0.288545 | 1.085 |
| Native, run 2 | 0.268696 | 0.288434 | 1.073 |
| Access, run 1 | 0.619467 | 0.896729 | 1.448 |
| Access, run 2 | 0.620214 | 0.902955 | 1.456 |

Median child-inclusive CPU seconds were 0.264107 -> 0.287698 and
0.267557 -> 0.287263 for native; 0.617737 -> 0.894860 and
0.618517 -> 0.900999 for access. Access-heavy overhead falls from about
62% to 45%; native overhead remains about 7-9%. These are separate warm
measurement sessions, not a controlled attribution of every timing difference.

A five-second `sample` profile used ten copies of the access workload.
Registered-pattern recognition accounted for 484 of 4,271 main-thread
samples, with 456 in pattern derivation. Those are inclusive sample counts,
not CPU instruction counts. Repeated derivation was a concrete optimization
target; binding and lowering remain substantial costs.

Each registered rule now retains a `MacroMatcher`. Patterns independent of
subject bindings are derived once. Context-dependent patterns are derived
against each subject. The matcher uses the existing Match cache, fixed-slot
rules, source views, and binding identity checks. Candidate selection still
runs the full matcher, calls the translator, and binds its replacement.
The collection translator also matches its source and queries types.
No process-global cache of scope-owned rule pointers was introduced.

## Physical source lines

Against `a56da260`, excluding generated `src/linked-meta.x` and bootstrap:

| File | Added | Removed | Net |
| --- | ---: | ---: | ---: |
| `src/transform.x` | 8 | 68 | -60 |
| `src/component-access.x` | 132 | 0 | +132 |
| `src/build.x` | 3 | 1 | +2 |
| `src/collect.x` | 28 | 12 | +16 |
| `src/compiler.x` | 2 | 0 | +2 |
| `src/expressions.x` | 3 | 0 | +3 |
| `src/macros.x` | 36 | 12 | +24 |
| `src/meta-native.x` | 2 | 2 | 0 |
| `src/meta-group.x` | 5 | 6 | -1 |
| `src/meta-sdk.x` | 29 | 0 | +29 |
| **Compiler total** | **248** | **101** | **+147** |

`lib/rewrite.x` is 20 lines, replacing the 14-line experimental implementation.
The prepared matcher adds 24 net lines to `lib/macro-value.x`.
The Type declarations add 13 lines to `lib/meta.x`; RPC wrappers, native target
registration, and the payload add 11 lines under `etc/`. Examples, test-home
staging, documentation, and generated artifacts are additional and are not
included in the compiler table. The 60-line kernel reduction does not offset
the component and integration costs.

## Verification and limits

- Two bootstrap-refresh/safe-build rounds and `make stage-diff-0` pass:
  bootstrap equals stage 0 across 268 generated C/H files.
- All 17 component examples pass, including [adoption](adoption.x),
  [precedence](precedence.x), and [binding-sensitive matching](../dispatch/bindings.x).
  The binding case produces `99 3 99` across global, shadowed, and global uses.
- The runtime unit binary passes 942 tests and 25,024 assertions.
- All 1,113 compiler fixtures were individually run with `run.sh check --fixture`:
  1,108 pass. `atomic-container-ops` and `var-helper-compound` fail only on
  the candidate because bound helper calls add prototypes; the former also
  changes transform binding references. `foreign-alias-body`, `keyword-aliases`,
  and `macro-construction-regressions` also fail on the baseline. The last two
  have byte-identical actual artifacts; foreign-alias diagnostics differ in
  checkout-relative versus absolute path spelling. `index-slice-lowering`
  passes in this complete sweep, superseding the earlier focused-run failure.
- Explicit protocol adoption invokes the custom setter exactly as the
  baseline does. Plain unadopted aliases retain base behavior. The three
  self-store/update/postfix probes reject on both compilers. User rewrite
  precedence and Map fallback pass.
- Installation into `/tmp/x2c-access-installed` and an adopted-setter build
  with `--meta-cc false` pass. After repairs, symbol-snapshot, header-cache,
  protocol, package-install, and meta-helper probe groups pass.
- `make doc-generate`, `make doc-check`, and `git diff --check` pass.

The native workload emits byte-identical C and H. The access workload has
byte-identical function bodies and H, but four additional helper prototypes
in C. Direct translation of the 23 fixtures finds C differences in
`typedef-collection-index-override`, `protocol-operator-index-matrix`, and
`var-helper-compound`; those differences are also helper prototypes.

`make verify` was attempted and failed. Its fixture runner stopped after
27 of 1,113 fixtures on `atomic-container-ops`, whose C adds helper prototypes
and whose transform now contains bound helper references and changed binding
numbers. That fixture passes on the baseline. Test-home failures from the
same run were repaired and their affected probe groups rerun successfully.
The later complete fixture sweep covers all 1,113 fixtures, as recorded above.
The complete `make verify` target has not passed and was not rerun after the
matcher optimization. No expectations were rebaselined.

Bootstrap transition note: when a builtin callback body changed, the old
compiler could no longer use its linked copy and attempted recursive helper
construction. The corrected callback definitions were built with registration
temporarily disabled, then the decorators were restored and ordinary refresh
and safe-build rounds converged. No bootstrap C/H was edited by hand. Routine
development across changed builtin definitions still needs this transition
considered; convergence alone does not prove that workflow convenient.

The byte-identical-C condition remains unresolved. Ordinary quotations bind
helper names, which causes the normal emitter to declare them. The old kernel
constructed those helper calls without the same binding information. No raw
AST workaround or helper-name exception was added to hide this difference.

Raw measurement samples and the temporary harness are retained under
`.context/language-components/builtin-access/`. Full command logs are under
`debug/access-*`. The current timing logs are
`access-matcher-final-timing1.log` and `access-matcher-final-timing2.log`;
convergence is recorded in `access-matcher-final-stage-diff.log`, and the
complete fixture summary is `access-matcher-full-fixtures.log`.


## Declaration ownership repair (2026-10-08)

The collector supplies function declarations from the public rows of each
actually emitted include. Source forwarding credits those declarations and
runtime umbrella modules. It does not credit private source include closures
or semantic compiler components. Header forwarding retains declarations needed
when cyclic includes reach inline bodies. Compile-time and project-meta
signatures retain forwarding because provider runtime headers can be absent.
The emitter still validates the resolved binding identity before consulting
this declaration inventory. No component helper-name exception or raw-name
call was introduced. Emission reads installed collector entries without
invalidating or recollecting them.

The repair adds 38 lines to `src/collect.x` and 12 net lines to
`src/generate.x`. The authored compiler delta from a56da260 is now +197,
excluding generated `src/linked-meta.x`. The component remains 132 lines and
the kernel transform reduction remains 60 lines. There is no total reduction.

Native synthetic C/H remains byte-identical to a56da260. Access H and function
bodies remain identical. The four added update/postfix prototypes are gone.
Access C now removes seven older redundant prototypes: `long_var`,
`Var_integer`, `Array_getindex`, `Map_getindex`, `int_var`, `Array_setindex`,
and `Map_setindex`. This is an explicit general declaration correction, not
a waiver of added-output requirements.

Reviewed expectation changes affect 129 C fixtures; every C delta deletes
prototype statements only. `atomic-container-ops.transform` records the
migration's bound calls and binding numbering. One `class-runtime.cc-stderr`
parameter-location note now names the header declaration. Unrelated AST,
symbol, and diagnostic expectations were preserved. Across 90 generated
bootstrap C files outside the changed owners, removing prototype lines and
blank lines leaves identical code; those files contain 4,435 fewer prototypes.
The collector header adds the two compiler methods. No bootstrap file was
edited manually.

Final verification:

- Bootstrap refresh and safe rebuild converge: `make stage-diff-0` matches
  all 268 C/H files.
- All 1,113 fixtures were checked individually: 1,108 pass. The five failures
  also fail on an unmodified c6129e75 compiler: `foreign-alias-body`,
  `generated-name-hygiene`, `keyword-aliases`,
  `macro-construction-regressions`, and `macro-template-lexical-shadow`.
  `atomic-container-ops` and `var-helper-compound` now pass.
- `make verify` still fails on `foreign-alias-body`; the complete target is
  not green. Its CLI, dependency, build, run, script, manifest, and state
  probes pass. Independent runtime checks pass 942 tests / 25,024 assertions
  and 23 thread tests / 89 assertions. All 17 component examples pass.
- Twelve repeated generations preserve hashes and sizes of all 18 C/H/.xi
  artifacts, totaling 14,805 bytes. A fresh process replays the provider .xi
  with identical client C/H/.xi. Cyclic inline headers compile with `-Werror`
  and execute successfully. Three meta-helper generations return 5 and keep
  cached C/H/.xi hashes identical. This bounded probe does not reproduce or
  disprove the historical gigabyte regression across every possible input.

Two quiet seven-pair warm translation runs after the repair measured:

| Workload | a56da260 seconds | Candidate seconds | Ratio |
|---|---:|---:|---:|
| Native, run 1 | 0.269141 | 0.290486 | 1.079 |
| Access, run 1 | 0.616210 | 0.896914 | 1.456 |
| Native, final run | 0.272705 | 0.296150 | 1.086 |
| Access, final run | 0.625364 | 0.919493 | 1.470 |

These measure the same synthetic translations without concurrent builds or
tests. They do not measure whole builds, runtime performance, or CPU
instructions. Declaration ownership repairs output, but the remaining access
translation overhead is substantial. No further extraction was attempted.
Evidence is under `.context/language-components/builtin-forward/`, with final
logs `debug/access-forward-final-{timing,compare,bounded,verify,runtime,thread,examples}5.log`
and `debug/access-forward-final-full-fixtures.log`. The work remains local;
no push or dev/main integration occurred.

Local repair checkpoint: `afce06ef` (`track declarations supplied by emitted headers`).
