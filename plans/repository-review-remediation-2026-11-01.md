# Repository review repairs and cleanup

> Status: active - plan only, recorded 2026-11-01.
> Findings were reproduced at `6125e8f693afa84d20be5ca96473360df5140075`,
> then `origin/dev`. Remote `dev` advanced to `b46aa0e12` during planning;
> that commit closes a separate decorator follow-up without repairing these
> findings. No repair or cleanup in this plan has been implemented.

## Scope and decisions

Address all twelve findings from the November 1 repository review in the
seven coherent changes below. Retain current compiler, runtime, package, and
test interfaces except for the explicitly selected String behavior change.
The [October 31 follow-ups](review-followups-2026-10-31.md) retain their own
ownership and completion records.

Settled with Gary:

- String slicing with step zero raises `bad-arg`, including on an empty
  String. Array, typed Array, List, and String follow the same rule.
- Historical benchmark measurements must stop being tracked. Remove them
  from the current tree and prevent their regeneration into tracked paths.
  Benchmark source programs and correctness fixtures remain useful inputs.
- Retain compact active calibration inputs so ordinary benchmark commands
  work from a fresh checkout. Remove historical samples and generated reports.
- Invoke the existing build driver for every requested package consumer.
  Gary accepted the repeated preprocessing and executable-link cost described
  in A, under the root `AGENTS.md` process ceiling.

No consequential design decision remains open. These decisions settle the
plan; they do not start implementation.

The other recommendations preserve established contracts. They do not require
new runtime representations, a package cache, a public build option, an
archive service, or an additional recurring gate.

## Changes and coverage

| Change | Review findings | Observable result |
| --- | --- | --- |
| A. Package build inputs and ordering | 1-3 | Changed compiler, translation flags, and link arguments take effect; cold consumers load native meta functions. |
| B. Literal values and printf lowering | 4 | Escaped percent signs consume the same arguments as their native C values. |
| C. Collection bounds and slices | 5-7 | Wide unsigned keys remain out of range; extreme slice steps are defined; zero steps consistently raise. |
| D. Test command summaries | 8 | Cleanup output does not erase test counts or change unmatched-filter status. |
| E. Examples and documentation | 9, 12a-12c | Expectations test supported behavior, examples compile, and prose describes current owners. |
| F. Beautification verification guidance | 11 | One workflow owns cadence and states what stage comparisons establish. |
| G. Historical benchmark cleanup | 10 | History is untracked, commands retain their required inputs, and installations exclude local evidence. |

### A. Package build inputs and ordering

Owner: [packages/package.mk](../packages/package.mk). Keep its flat
`builds/*.c`, `*.h`, and `*.xi` interface and the native driver's existing
incremental compilation.

Add one local translation-invocation record under `builds/`. Record the
selected compiler command/path, its existing `x2c env identity`, and effective
`PACKAGE_X_FLAGS`. Compare before replacing the record so unchanged input
does not make translation stale. Generated products depend on that record,
the selected compiler file, and prerequisites from existing included `.d`
files.
This also covers a changed wrapper and selection of an older compiler path.
Obtain identity lazily in the record recipe and fail if that command fails.
Do not make `make clean` require a working compiler.

Refresh `.native.rsp` from effective `PACKAGE_LINK` with the same
compare-before-replace approach. Make native-module preparation an order-only
prerequisite of the package archive. Generic and custom consumers already
depend on that archive, so one edge establishes their ordering. The module
depends on translation, not the archive; the driver already excludes a
package's own archive when building its sources. Preserve the no-module case.
Give Torch's module the native-object prerequisites its archive already has.

Archive readiness alone does not establish consumer freshness: link arguments
or a module can change while archive bytes and timestamps remain unchanged.
Use one shared consumer prerequisite list containing `$(PACKAGE_ARCHIVE)`
and the existing `package-build-force`. Apply it to both generic rules and
the custom rules in pcre2, raylib, termbox2, autodiff, and Torch. Keep the
source prerequisite first so `$<` remains correct. Document that shared list
alongside the custom-rule convention.

Every requested consumer then invokes `x2c build`, which already checks its
imported sources, native modules, and current package arguments. Do not add
a second consumer fingerprint or optional-module state record in Make.
Translation and C-object reuse remain available, but executable builds still
preprocess and link. This repeated work is explicitly accepted.

Full delegation to `x2c build` is a larger alternative. Its translation
fingerprints work, but its private `gen/<stem-hash>` layout does not supply
the package's flat public artifacts. Do not add a public export option or
couple Make to that private layout for these repairs.

Extend the existing CLI-boundary probe with an inert package. Check
`CHOICE=7` followed by `CHOICE=9`, compiler replacement, `-lm` followed by
`-pthread`, and unchanged translation/response timestamps. Extend the existing
native-module probe's `tally` package to exercise cold direct and parallel
consumers. Reproduce raylib's desktop-to-memory response change without
opening a window. Change only `PACKAGE_LINK` between two inert libraries and
verify the consumer's returned value changes while its package archive stays
unchanged. Likewise change a module's linked dependency and verify the
compile-time consumer updates. Preserve translation/object reuse and existing
probe status; do not require an executable link to be skipped. If the separate
REPL probe issue blocks the full native-module script, report that boundary
and validate its package segment independently.

Small-source probes measured median elapsed times over five warm runs:
identity lookup 0.0380 seconds and forced translation 0.7753 seconds. A real
consumer importing that package took 0.1007 seconds per warm invocation
(range 0.0971-0.1025), including preprocessing and relinking. That consumer
measurement excludes package preparation and module rebuilding; larger
programs can cost more. The selected design adds one identity lookup per
package invocation and a driver invocation per requested consumer. It keeps
Make's existing timestamp/depfile model for flat translation; broader
include-search/content freshness remains a separate design.

### B. Literal values and printf lowering

Owners: [printf-format.x](../src/components/printf-format.x),
[stage.x](../src/stage.x), [scan.x](../lib/scan.x), and
[string-switch.x](../src/components/string-switch.x), with static-format
eligibility in [expressions/calls.x](../src/expressions/calls.x).

The review reproduced incorrect Var conversion for `"\045d %s"` and
`"\x25i %s"`. Planning also found that `Compiler.literal_text_value`, reached
through `Code.value`, uses `String.unescape` and disagrees with native C for
long hexadecimal escapes, embedded NUL, and universal character escapes.
Therefore substituting `String.parse` or the current `Code.value` alone is
insufficient.

Extend the scanner's existing C escape operation to expose decoded values
without changing its current signatures or status rules. Correct the
compiler value reader through that owner, preserving adjacent token
boundaries and LF/CRLF continuations. Use the existing encoder in
`lib/encoding.x` for universal characters. A canonical String value ends at
the first decoded NUL; the native C array keeps its full bytes.

Keep `Code.format` as the printf eligibility check and spelling API. Scan
decoded `Code.value` bytes and remove quote slicing and escape skipping.
Replace String-switch's duplicate decoder with the same value path. Native
macro words that the compiler cannot evaluate must remain nonconstant,
rather than being skipped. Make `Compiler.printf_static_format` check the
whole spelling, not just its outer quotes. String-switch must select its
native-spelling fallback before calling `Code.value` on a nonconstant label.
Preserve printf's static-Var restriction.

Preserve native arguments, shadowed functions, the seven printf families,
runtime `String.parse`/`unescape`, and percent/collection literal semantics.
Do not add prefixed or wide literals, or change the ordinary character
literal's existing `char` result and implementation-defined cases.

Extend `printf-var-lowering` and the existing meta-value fixtures. Compare
native and compile-time values for octal percent, `\x025i`, escaped
backslashes, adjacent literal pieces, NUL termination, and supported universal
escapes. Include width/precision consumption and a following `%s` to expose
argument drift. Generated C must compile without warnings and print the
expected values. Exercise `adjacent-c-literals`, `promoted-string-cache`,
and String-switch fixtures as connected consumers. Existing unsupported
format fixtures retain their contracts.

### C. Collection bounds and slices

Owners: [List traversal](../lib/list/traversal.x),
[common slicing](../lib/common.x), [Array generics](../lib/array/generics.x),
and [String editing](../lib/string/editing.x).

- In `List.get`, compare integer keys with `INT_MIN` and `INT_MAX` through
  `Var.integer_compare` before converting. Give limit macros an explicit
  native type for boxing. `ULLONG_MAX` and
  `ULLONG_MAX - 1` must return void instead of the last two list values.
  Keep ordinary negative indexing, non-integer association lookup, and its
  absence result unchanged.
- Keep normalization in `x2c_normalize_slice`. Widen negative-step magnitude,
  count arithmetic, and the `length + 1` forward-stop adjustment. Use a
  count-controlled Array loop with a `long long` index and widen String's
  running index. This keeps the final advance representable without an extra
  per-element branch. Preserve Array's contiguous fast path and apply its
  template repair to typed Arrays. List needs the shared normalizer repair,
  not another traversal mechanism.
- Let the shared normalizer reject String step zero before the empty-input
  return. Update its API comment, the collection guide, generated API
  documentation, and the
  appropriate release note. This is the selected compatibility change.

Extend the existing List, Array, typed Array, String, and `test-index-slice.x`
suites with boundary cases. Use three-element inputs with `INT_MAX` and `INT_MIN`
steps, empty inputs, reversed bounds, and ordinary negative steps. Repeat the
review's focused UBSan probe over emitted collection objects. Test the
normalizer directly with logical length `INT_MAX`, without a large allocation.
Preserve public signatures, canonical String identity, and collection
ownership. Use existing
performance checkpoints when the final hot-path diff warrants them.

### D. Test command summaries

Owner: [commands/test/main.x](../commands/test/main.x).

Search captured output backwards for the existing complete summary line,
instead of assuming it is the last line. Preserve the child status as the
failure authority and the existing zero-match rule. Do not add a wire
protocol or require test cleanup to be silent.

Extend [the command's tests](../commands/test/tests/run.sh) with a deferred
print after `Test.main`. A passing test must still count as one pass. An
unmatched filter must still exit 2; a real failing program must still fail.
Keep ordinary programs without summaries, `--quiet`, `--list`, and ordered
parallel output working through their existing checks.

### E. Examples and documentation

Make these small repairs together because they reconcile consumers with
already established behavior:

- Give `love/basic-literals` and `power/derive` deterministic Map output
  through named lookups. Preserve nested-map conversion and record equality
  coverage. Where traversal is the demonstration, use sorted keys, following
  `power/channel-word-count`. Apply that to `love/maps` and remove its special
  output-sorting branch from `examples/check.sh`. Do not freeze Map table
  order or build a general output normalizer.
- Classify `apps/notes/bench/notes-database.x` as an optional probe in
  `examples/manifest.txt`, alongside the other Notes benchmarks.
- Refresh only autodiff's `autodiff-checkpoint-return` and
  `autodiff-unsupported` diagnostic expectations through its existing fixture
  update target. Retain the rejection cause and source location; include the
  current macro-expansion provenance.
- Rename the contextual-keyword example's `remainder` function in the
  language reference to avoid the implicit C math declaration.
- Mark the PCRE2 import fence in `power-10-imports.md` with the site's existing
  package-dependent `x2c,ignore` convention and explain its prerequisite.
  Preserve package-owned execution checks rather than fetching dependencies
  in the general documentation sample sweep.
- Qualify the Channel guide's condition-wait claim as applying to native
  threads. Link to the existing explanation of scheduler-parked tasks.

Run the existing examples check, autodiff fixtures and examples, affected
documentation samples, and documentation audit. Regenerate derived
documentation through its targets. Keep expected-output updates limited to
these intentional changes.

### F. Beautification verification guidance

Owners: [the source standard](../agents/x2c-code-standard.md) and
[the beautification skill](../agents/skills/beautify-x2c-source/SKILL.md).

Keep cadence in the skill: verify one coherent change, including related
files. Replace the standard's conflicting per-file instruction with a link
to that owner. State that stage comparisons compare outputs produced by
different stages of the current tree. They do not automatically compare
with pre-edit output. When preservation is the claim, use the actual saved
before/after evidence already called for by the task.

Check both documents against the Makefile targets and run the documentation
audit. This removes duplicated policy and a false proof claim without adding
a build, gate, or recurring step.

### G. Historical benchmark cleanup

Remove historical output in a normal forward change. Keep local copies in
ignored locations where useful; existing Git history retains the original
tracked evidence. There is no history rewrite or external storage project.

The tracked inventory at the reviewed revision is:

| Output to untrack | Files | Bytes |
| --- | ---: | ---: |
| `examples/shootout/results/` | 1,552 | 65,838,843 |
| `examples/shootout-unofficial/results/` | 2 | 139,502 |
| Torch benchmark reports, plots, and saved result JSON | 17 | 614,173 |
| `unittest/benchmarks/hash-table/results/` | 5 | 45,312 |
| Hash-table `RESEARCH.md` experiment report | 1 | 32,747 |

The Torch set contains `HISTORICAL-20260910.md`, `MATCHED.md`, `PILOT.md`,
`REMEDIES.md`, `REPORT.md`, `SUPPLEMENT.md`, seven PNGs, and four JSON files
under `results/chains-20260911/`.

Before removal, preserve current workload-selection and parallelism
explanations in the shootout README. Extract one reusable current chart
renderer and its requirements into `examples/shootout/tools/`; discard
duplicated run-specific copies with their history. Replace hardcoded claims
about pinned references and execution modes with report-derived labels or
neutral wording. Keep benchmark programs,
reference sources, specifications, attribution, manifests, correctness
fixtures, and current operating instructions.

With the selected calibration policy, compact both shootout baselines.
Drop unused raw reference measurement arrays. For exact output checks, use
the already stored `stdout_sha256` instead of base64 copies of large output.
Keep the small expected values required for numeric tolerance comparisons.
Make calibration writers emit this compact format too, with raw observations
remaining in ignored output directories.
Preserve reference statistics, source/input identities, methodology, host
checks, and provenance. Estimated sizes are 54,842 bytes for the active
baseline, formerly 3,508,036, and 34,209 for the legacy baseline, formerly
109,453. Do not recalibrate or alter measured statistics. Their file hashes
change, so snapshot comparison must continue to distinguish baseline
identities. Remove `legacy` from
`unittest/benchmarks/build-scaling-baseline.json` and its carry-forward code
from `tools/build-scaling.py`. Preserve legacy history-reader support.

Redirect producers to existing ignored destinations:

- Shootout promoted reports: `examples/build/shootout/results/current.*`.
  The legacy harness uses `examples/build/shootout-unofficial/results/`.
- Torch reports and plots: `debug/torch-comparison/<run-id>/`, beside inputs.
- Hash-table output stays under `unittest/build/benchmarks/hash-table/`.
  Nightly history stays under the existing `debug/performance-history/` owner.

Add explicit ignores for retired result trees and Torch output names after
the existing broad re-inclusions in `.gitignore`. Remove tracked outputs
with the corresponding index changes; ignore rules alone do not untrack them.

Update both suite READMEs, the examples index, Torch instructions/templates,
and `site/BENCHMARKS.md`. Remove duplicated dated tables and stale "latest"
claims. Replace historical artifact links in retained plans and prose with
immutable links to the pre-removal commit. Preserve plan decisions and
outcomes; do not delete archived plans. No site page currently consumes the
benchmark JSON, and this change does not implement the future benchmark page.

Finally, exclude both shootout result trees and calibration files from
`etc/x2c-payload.x` example copying. It walks the filesystem, so ignored local
history can otherwise leak into installations. The review's helper copied
71,012,633 example bytes, including 65,795,812 shootout-result bytes and the
3,508,036-byte active baseline. These are copied bytes, not compressed
release size.

Validate baseline loading, unchanged ratios, output-mismatch rejection,
numeric tolerance, and producer destinations with small saved-data inputs.
Use `examples/shootout/tools/test_shootout.py`,
`tools/test-performance-snapshot.py`, `tools/test-build-scaling.py`,
`tools/test-build-scaling-history.py`, and Torch's
`packages/torch/benchmarks/test-comparison.py` for their affected contracts.
Verify fresh-checkout inputs for `shoot-check`,
`shoot-run`, `shoot-update`, build-scaling, and performance snapshots without
a new timing campaign. Use `unittest/probes/run-package-install.sh` for the
payload check, with ignored history deliberately present. Check that installed
examples remain usable, output
paths stay ignored, and no tracked reference points to a removed local file.

## Order, verification, and delivery

A-D are independent correctness repairs. E and F can proceed independently;
E's final fixture refresh follows any overlapping compiler repair. G is also
independent. Within G, preserve operational inputs and redirect producers
before removing tracked output.

Implement and validate these as coherent changes, without requiring seven
separate publication gates. Existing root `AGENTS.md` owns integration,
performance applicability, generated artifacts, and delivery. Keep optional
checks optional and use the existing focused suites for regression cases.

The last implementation step for each delivered batch is to review and fix
the completed authored diff, including deletions and consumer references.
Then run `git diff --check` and the applicable existing publication validation
on the final integrated tree. Review generated deltas too. This planning-only
request stops with the plan and does not authorize repair or publication.

## Design review

Each repair remains at its current owner: Make supplies package translation
inputs, compiler staging interprets literals, common slicing normalizes
bounds, and the test command interprets its existing summary. The plan
removes an example-runner special case, duplicate verification policy,
historical outputs, and duplicated evidence renderers. It preserves runtime
ABI, ownership, and ordinary package layouts. String error behavior, compact
calibration retention, and repeated consumer-build cost are explicitly
settled. No whole compiler mechanism was established as disposable by this
review, so none is scheduled for speculative removal.
