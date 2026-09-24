# Porting the repository's tooling to x2c scripts

> Status: active - refreshed against dev at `1aaf9479` on 2026-09-24.
> The extensionless tool rename, the llms.txt generator port, the
> documentation sample check ports and the `tools/check-docs` port are
> delivered, and on 2026-09-24 every row of the ready table except the
> release.yml step; later release, gate and compiler-backed ports remain
> separately sequenced.
> Continues `plans/archive/x2c-scripting-library.md`, whose four phases shipped the
> scripting primitives; this plan decides where the remaining effort goes.

## The result

The repository's own automation runs as x2c scripts wherever that is a
translation of what the tool already does, the runtime gains the few
operations those translations need, and the tools that cannot or should not
move are named so nobody spends effort on them.

## Survey

The 2026-09-16 spike at `756ed8e` classified every third-party-language
file outside `bootstrap/` and `builds/`: 68 Python, 45 shell, 21 JS/TS,
3 expect scripts, 4 workflow files, and the Makefile recipes, about 32,800
lines. Three findings decided the ranking.

- **Regular expressions were the widest gap.** 16 Python files held 235
  `re.` sites and the gate probes 8 `grep -E` calls. Six files hold 172 of
  those sites, and all six lex x2c source with patterns: `x2c_source.py`,
  `x2c_symbols.py`, `audit-source-bloat.py`, and the three skill analyzers.
- **Line diff was the next.** 32 `diff` calls in the probes and difflib in
  the check modes of the doc generators.
- **A clock is the third.** Eight benchmark drivers, `harness-metrics.py`,
  and `agent-failure.py` need timing or a formatted date.

Everything else the tools do, the scripting library already covered.

## September 22 refresh

The rename campaign is complete. Commit `2d188c42` renamed the only two
executable x2c scripts under `tools/` to `tools/check-release` and
`tools/gen-package-index`, retaining their x2c shebangs and executable bits.
Direct execution and explicit `x2c script <path>` produce the same output and
status for both. `src/utils.x` already classifies any shebang file as x2c
source, so no suffix fallback or second launcher was needed.

The remaining `.x` files under `tools/` are not missed rename candidates.
`tools/repl-spike/api-check.x` and `retention.x` are non-executable compiler
inputs. `tools/x2c-graph/*.x` are modules linked into one native executable,
and the files below its tests directory are fixtures.

The current tree also changes the porting order recorded by the September 16
survey:

- The former `tools/gen-llms-txt.py` did not wrap prose and therefore never
  needed `String.wrap`; current `Regex`, `Diff`, `Path` and `Args` covered its
  completed port to `tools/gen-llms-txt`.
- `Job.wait_any` now supplies the concurrency operation that
  `tools/check-doc-examples.py` was waiting for.
- `tools/release-candidate.py`, `tools/gen-lisp-init.py` and
  `tools/performance-snapshot.py` were added after the survey and need an
  explicit disposition rather than silently falling outside the campaign.
- The meta coverage tools and the expanded REPL probes reinforce the existing
  compiler-interface and host-PTY boundaries; they do not create simple
  translation candidates.

## Next campaign: documentation tooling parity

Deliver this campaign in two independently reviewable changes. Both changes
name the resulting scripts without `.x`, keep an x2c shebang and executable
bit, update every live caller, and delete the replaced Python file after
parity is established.

Before removing either Python owner, add its predecessor and replacement
measurements to `tools/x2c-script-ports.md` while both versions can still run.
That ledger owns physical line counts, direct modules, host commands, parity,
port complications and any representative timing worth retaining.

### 1. Port the llms.txt generator - delivered

`tools/gen-llms-txt` replaces `tools/gen-llms-txt.py` and preserves the
default stdout mode, `--write`, `--check`, diagnostics, chapter ordering,
absolute link rewriting and byte-identical `site/public/llms.txt` and
`llms-full.txt` output. Use `Regex`, `Diff`, `Path` and `Args`; keep URL-path
normalization as a small private operation in this script rather than adding
a general URL library.

Before the Python owner was deleted, both implementations ran on the same tree
with matching status, stdout and stderr in all three modes. The saved Python
generated files and x2c writer output also matched byte for byte. `make
doc-check` and `make site-check` cover the live callers after the rename.

### 2. Port the documentation sample checks - delivered

Replace `tools/check-doc-examples.py` and `tools/check-gallery-examples.py`
with extensionless x2c scripts. Add one non-executable
`tools/doc-samples.x` module for the code-fence parser, `Sample` record,
dedenting and hidden-line handling that the current gallery checker imports
from the example checker. Compilation and execution stay in
`check-doc-examples`; gallery mappings, links, manifest coverage and
`--update` stay in `check-gallery-examples`.

Run independent samples as `Job`s up to the existing `JOBS` limit and collect
them with `Job.wait_any`. Store results by input index so diagnostics remain
in document order. Do not add a worker framework or another process API.

Run the Python and x2c implementations on the same complete tree and compare
status, stdout and stderr for the ordinary and `--outputs` example checks and
the ordinary and `--update` gallery paths. Exercise `--update` in a temporary
copy so the repository is not rewritten during parity testing. Finish each
delivery with `git diff --check` and
`tools/gate-state.py ensure agent-pr-check` on the exact final tree.

Delivered as `tools/check-doc-examples`, `tools/check-gallery-examples` and
`tools/doc-samples.x`. On the same tree, the ordinary and `--outputs` example
checks matched in status, stdout and stderr; the only stderr differences in
the failing ordinary run were temporary directory names and translation
times inside compiler diagnostics. The ordinary and `--update` gallery paths
matched in status, stdout, stderr and rewritten examples in two temporary
copies, apart from the intended new command name in the `--update` hint.
Neither version enforces a per-sample run time now; the Python version's
30-second limit ended the whole check with a traceback, and `Job` has no
timeout.

### 3. Port the documentation audit - delivered

`tools/check-docs` replaces `tools/check-docs.py` in the same place in
`make doc-check`, with the same checks, messages and exit status. It still
invokes the Python catalog and API generators in `--check` mode, now
concurrently. On the current tree, on a missing `builds/0`, and on broken
copies covering every check, both versions matched in status, stdout and
stderr; only the error order of the flag and workflow checks differed,
because Python iterated sets there.

## Ruling on gate tooling

`plans/archive/x2c-scripting-library.md` kept `check-generated-stages.sh`,
`check-conformance-coherence.sh`, and `gate-state.py` in shell and Python
so that a check which detects a broken compiler does not sit behind the
compiler's scripting feature. Gary accepted the first gate probe in x2c on
2026-09-16 (`unittest/probes/run-suite-coverage`) on this reasoning: a probe
that is itself an x2c script fails loud when the compiler regresses, since
its build stops the gate, so it cannot hide the regression it exists to
catch. That covers probes that run the compiler and compare text, and
`tools/check-conformance-coherence` moved to x2c under it on 2026-09-24.

Two things stay outside that ruling. The fake toolchain shims under
`unittest/probes/fake-*.sh` are executed by the compiler under test as its
`cc` and `ar`, so they must exist before any x2c runs. The stage-diff
check, `gate-state.py`, `configure`, and `site/public/install.sh` run
before or around the compiler itself; converting any of them is Gary's call,
not a routine port.

## Library work, in the order of ports unblocked

Rechecked against dev 29326dbd on 2026-09-24. None of the three is worth a
library addition now; each is added with its first real consumer, if one
appears.

1. **Clock and time: declined.** A script includes `<time.h>` and calls
   `clock_gettime` and `strftime` directly, as `src/report.x`,
   `src/build.x` and `lib/logger.x` do, and `$time` in
   `lib/system-macros.xmacro` already times a statement. The listed
   consumers mostly do not need it: the seven `run-*.sh` drivers take
   timings from the benchmark binaries, `tools/harness-metrics.py` reads
   timestamps from its records, `tools/agent-failure.py` needs one ISO date,
   and `hash-table/direct/run.sh` makes one `date -u` stamp. Only
   `tools/performance-snapshot.py` needs both, and it also needs host
   locking, signals and timeouts.
2. **`String.wrap(width)` and a median: deferred.** `wrap` is about 15 lines
   of `.x`. Its consumers are the 16-line `textwrap` block in `etc/help.mk`
   and the two doc generators, whose ports put it in `tools/definitions.x`
   as `Prose.wrap` on 2026-09-24. A median is about 8 lines;
   its consumers are the awk `median` functions in
   `run-lisp-auto-benchmark.sh` and `run-match-cache-benchmark.sh`, about 15
   lines each. Write either inside the port that uses it.
3. **Byte reads on `Path`: declined.** The only byte consumer is one `od`
   line reading a 24-byte PNG header in the 19-line
   `packages/raylib/verify-renders.sh`; `fopen` and `fread` cover it. The
   mode bits in `tools/gate-state.py` come from `lstat`, not file bytes.

Not worth building, because every consumer is off the table: an HTTP server,
sockets, a pty, YAML, zip, statistics beyond a median, plotting.

## Ports that need nothing more from the library

Delivered on 2026-09-24 except the release.yml step; each port's parity
evidence is its row in `tools/x2c-script-ports.md`. Each is a translation of what the tool does today. Port each with the same
proof the earlier conversions used: run both versions on the same inputs and
compare status and output.

| Tool | Lines | Notes |
| --- | --- | --- |
| `examples/programs/check-reference-lisp.py` | 261 | `Args`, job capture, `Path.temp_dir` |
| `unittest/probes/run-artifact-atomicity.sh` | 52 | gate |
| `unittest/probes/run-scope-shutdown.sh` | 140 | gate |
| `unittest/probes/run-error-floor.sh` | 100 | gate |
| `unittest/probes/run-build-recovery.sh` | 77 | optional |
| `tools/check-conformance-coherence.sh` | 50 | `Diff.unified`; see the ruling above |
| release.yml "assemble the release directory" step | ~40 | already calls `gen-package-index`; version agreement and `SHA256SUMS` are the same job |
| `packages/libcurl/verify-profile.sh` | 39 | file checks |
| `packages/blis/verify-archive.sh` | 46 | `nm` through a job, `json.x` |

The four gate probes share `unittest/probes/probe.x`: the repository root,
environment defaults, a `probe_fail` that prints and exits 1, the build-mode
flags read from `etc/build-mode`, and a scratch directory reset. None of the
four compares expected output, so it has no diff helper yet; the larger
probes still copy their prelude by hand.

## Ports after the library items

| Tool | Lines | Needs |
| --- | --- | --- |
| `tools/gen-module-catalog.py` | 134 | delivered 2026-09-24 with `gen-api-reference.py`; see `tools/x2c-script-ports.md` |
| `tools/gate-state.py` | 390 | mode bits, uuid; see the ruling |
| `tools/repo-metrics.py` | 373 | delivered 2026-09-24; see `tools/x2c-script-ports.md` |
| `unittest/compiler-fixtures/run.sh`, `examples/check.sh` | 314, 257 | `Diff.unified`; the awk manifest parsing is `String.split` |
| `run-package-install.sh`, `run-preprocessor-boundary.sh`, `run-symbol-snapshot.sh`, `run-raw-symbol-sweep.sh`, `run-varops-fatal.sh`, `run-expression-bodied-functions.sh` | 87-237 | the probe module; `wait_any` replaces `xargs -P`; the last one's Python AST comparison is already `compare-ast` |
| `run-protocol-boundaries.sh`, `run-header-cache.sh`, `run-cli-boundary.sh` | 536-1344 | the probe module; volume, and nine inline Python snippets in the CLI probe |
| `unittest/benchmarks/run-*.sh` (8) | 28-122 | clock, median |
| `tools/harness-metrics.py`, `tools/agent-failure.py` | 509, 503 | date formatting |
| `etc/cosmopolitan/verify-ape.sh`, `build-ape.sh` | 82, 60 | nothing; low value alone |
| `tools/x2c-graph/tests/run.sh` | 1001 | volume only |

## Post-survey tools

| Tool | Disposition |
| --- | --- |
| `tools/release-candidate.py` | A real x2c candidate with no known library gap. Plan it as a release-safety delivery with its offline fake-`gh` tests and immutable-byte checks, not as routine cleanup. |
| `tools/gen-lisp-init.py` | Keep in Python for now. It is a small bootstrap generator invoked during bootstrap refresh; moving it behind script compilation adds bootstrap coupling without meaningful source deletion. |
| `tools/performance-snapshot.py` | Keep in Python until clock/date, host locking, process-group timeout and streamed-output behavior have ordinary x2c owners. |
| `tools/repl-spike/check.py`, `retention.py` | Keep as host-side PTY and measurement drivers. The x2c programs they exercise are already x2c source. |

## Rewrite on the compiler instead of translating

These tools contain a second parser for x2c source, written as regular
expressions. Translating them would keep that parser, so they are not
ported here. On 2026-09-24 this rewrite, including catalog item C09, moved
into [x2c lint, format, and compiler-backed source tools](x2c-lint-and-format.md),
which sequences the doc generators, metrics, and the skill analyzers over
one shared compiler definition walk. The indentation syntax has landed, so
the new scripts use it.

## Off the table

| What | Why |
| --- | --- |
| `site/public/install.sh`, `configure` | run before any x2c exists; POSIX sh |
| `unittest/probes/fake-*.sh` | executed by the compiler under test as its toolchain |
| `packages/torch` tests and benchmarks (about 4,600 lines) | exist to run PyTorch and matplotlib |
| `packages/libcurl/tools/run-fixture.py`, `examples/packages/http-json-releases/tools/run-fixture.py` | need an HTTP server |
| `packages/termbox2/tests/*.expect` | drive a pty |
| `packages/tools/deps.py`, `test-deps.py` | HTTP download, zip, `flock`; white-box mock tests |
| `packages/torch/tools/gen-ops.py` | YAML and heavy regex over a foreign schema |
| `examples/shootout/tools/shootout.py`, `unittest/benchmarks/hash-table/{run,research,compare}.py`, `run-udb3.sh`, `run-jackson.sh` | statistics, provenance, and network clones of foreign suites |
| `site/` Astro and Shiki modules, `etc/vsc-extension/`, `site/tests/`, workflow YAML glue | live inside Node, VS Code, or the Actions runner |
| `site/scripts/dev.mjs` | TCP port probing |
| `etc/help.mk` Python | too small to matter until `String.wrap` exists |

## Landed on the way

- `lib/regex.x`: `Regex.compile`, `match`, `match_from`, `find_all`,
  `split`, `replace`, `replace_all`, `replace_fn`, `escape`,
  `capture_names`; a `RegexMatch` indexed by number or name. A byte-oriented
  backtracking engine with the same method names as the pcre2 package;
  Gary chose it over vendoring PCRE2 or making the package the only regex,
  so gate tooling has no package dependency. A repeated group raises
  `<size-limit>` past 2,000 repetitions in one match; repeated byte classes
  run as a loop and have no limit.
- `lib/diff.x`: `Diff.lines` and `Diff.unified`, Myers over the trimmed
  middle, wholesale replacement past 2,000 edits.
- `x2c script` runs a file of any name whose first line is a shebang;
  `x2c_source_file` in `src/utils.x` is the one classifier. The two new
  tools are `unittest/probes/run-suite-coverage` and `packages/tools/bundle`,
  without an extension and executable. Commit `2d188c42` subsequently gave
  the two executable x2c scripts under `tools/` extensionless names as well.
- `packages/tools/bundle` is byte for byte the Python bundler's output on
  pcre2, and BUNDLE.json now has one owner beside `src/install.x`.
- Two defects fixed: a script under a package directory was linked as a
  consumer of itself (`src/build.x`), and `Var.json` rejected a bare map
  key longer than ten characters, a long symbol (`lib/json.x`).
- The raw-symbol sweep classifies any swept shebang file as a script unit,
  not only those under `compiler-fixtures/`.

## Plan review

- **Facts established elsewhere.** The per-file classification is the
  spike's survey and each port re-derives nothing from it; a port proves
  itself by running both versions on the same inputs. The gate ruling above
  is Gary's decision, recorded once.
- **Reuse and deletion.** Every port deletes its Python or shell source and
  a Makefile or workflow line changes to call the script. The documentation
  sample module replaces code the gallery checker currently imports from the
  example checker; the probe module replaces a prelude copied into seventeen
  shell files. No registry, cache, or second launch path is added.
- **Idiomatic.** Ports use `Job`, `Path`, `Args`, `Json`, `Regex`, and
  `Diff` as any script does; the compiler-backed rewrite reads `.xi` data
  through `List` and `Match` as `tools/x2c-graph` does.
- **Validators and fixtures.** The documentation tranche uses the Python
  implementations as temporary parity oracles and existing doc/site gates as
  the durable proof. It adds no recurring gate or dedicated negative fixture.
