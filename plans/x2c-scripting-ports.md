# Porting the repository's tooling to x2c scripts

> Status: active - 2026-09-16. The survey is done and the first three items
> landed: `lib/regex.x` (`31f9b95`), `lib/diff.x` with the first gate probe
> and the package bundler as scripts (`9b3a0fa`), and script files of any
> name (`e777f99`). The rest of this plan is the ordered work that remains.
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

## Ruling on gate tooling

`plans/archive/x2c-scripting-library.md` kept `check-generated-stages.sh`,
`check-conformance-coherence.sh`, and `gate-state.py` in shell and Python
so that a check which detects a broken compiler does not sit behind the
compiler's scripting feature. Gary accepted the first gate probe in x2c on
2026-09-16 (`unittest/probes/run-suite-coverage`) on this reasoning: a probe
that is itself an x2c script fails loud when the compiler regresses, since
its build stops the gate, so it cannot hide the regression it exists to
catch. That covers probes that run the compiler and compare text.

Two things stay outside that ruling. The fake toolchain shims under
`unittest/probes/fake-*.sh` are executed by the compiler under test as its
`cc` and `ar`, so they must exist before any x2c runs. The stage-diff
check, `gate-state.py`, `configure`, and `site/public/install.sh` run
before or around the compiler itself; converting any of them is Gary's call,
not a routine port.

## Library work, in the order of ports unblocked

1. **Clock and time.** `Clock.monotonic()` for timing and a `strftime`
   wrapper for dates. `lib/logger.x` has both privately in `_capture_time`
   and `_write_absolute_time`; the module lifts them. Consumers: the eight
   `unittest/benchmarks/run-*.sh` drivers, `tools/harness-metrics.py`,
   `tools/agent-failure.py`, and the timestamped result directories in
   `unittest/benchmarks/hash-table/direct/run.sh`. Ship it with the first of
   those ports, as `lib/time.x` was deferred until a consumer existed.
2. **`String.wrap(width)` and a median.** Consumers: `gen-api-reference.py`,
   `gen-module-catalog.py`, `gen-llms-txt.py`, the `make help` Python in
   `etc/help.mk`, and the benchmark drivers' awk statistics.
3. **Byte reads on `Path`.** `Path.read_text` refuses binary files.
   Consumers: `packages/raylib/verify-renders.sh` and the mode bits in
   `tools/gate-state.py`.

Not worth building, because every consumer is off the table: an HTTP server,
sockets, a pty, YAML, zip, statistics beyond a median, plotting.

## Ports that need nothing more from the library

Each is a translation of what the tool does today. Port each with the same
proof the earlier conversions used: run both versions on the same inputs and
compare status and output.

| Tool | Lines | Notes |
| --- | --- | --- |
| `examples/programs/check-reference-lisp.py` | 235 | `Args`, job capture, `Path.temp_dir` |
| `tools/check-gallery-examples.py` | 112 | the gallery data it loads with `importlib` becomes a JSON or `.x` table |
| `unittest/probes/run-artifact-atomicity.sh` | 52 | gate |
| `unittest/probes/run-scope-shutdown.sh` | 140 | gate |
| `unittest/probes/run-error-floor.sh` | 100 | gate |
| `unittest/probes/run-build-recovery.sh` | 77 | optional |
| `tools/check-conformance-coherence.sh` | 50 | `Diff.unified`; see the ruling above |
| release.yml "assemble the release directory" step | ~40 | already calls `gen-package-index.x`; version agreement and `SHA256SUMS` are the same job |
| `packages/libcurl/verify-profile.sh` | 39 | file checks |
| `packages/blis/verify-archive.sh` | 46 | `nm` through a job, `json.x` |

Do the four gate probes together behind one shared
`unittest/probes/probe.x` module: repository root, `X2C`, `CC`, and `AR`
defaults from the environment, a `fail` that prints and returns 1, the
build-mode flags read from `etc/build-mode`, a scratch directory reset, and
`Diff.unified` for expected output. Every shell probe copies that prelude
by hand today; the module is the first thing the larger probes will need.

## Ports after the library items

| Tool | Lines | Needs |
| --- | --- | --- |
| `tools/gen-module-catalog.py`, `gen-llms-txt.py` | 134, 236 | wrap; `Diff.unified` for `--check` |
| `tools/check-docs.py` | 395 | regex, done |
| `tools/gate-state.py` | 360 | mode bits, uuid; see the ruling |
| `tools/repo-metrics.py` | 375 | column formatting |
| `tools/find-redundant-conversions.py` | 254 | regex, done |
| `tools/check-doc-examples.py` | 199 | threads and `Job.wait_any` replace the pool |
| `unittest/compiler-fixtures/run.sh`, `examples/check.sh` | 314, 257 | `Diff.unified`; the awk manifest parsing is `String.split` |
| `run-package-install.sh`, `run-preprocessor-boundary.sh`, `run-symbol-snapshot.sh`, `run-raw-symbol-sweep.sh`, `run-varops-fatal.sh`, `run-expression-bodied-functions.sh` | 87-237 | the probe module; `wait_any` replaces `xargs -P` |
| `run-protocol-boundaries.sh`, `run-header-cache.sh`, `run-cli-boundary.sh` | 536-1344 | the probe module; volume, and nine inline Python snippets in the CLI probe |
| `unittest/benchmarks/run-*.sh` (8) | 28-122 | clock, median |
| `tools/harness-metrics.py`, `tools/agent-failure.py` | 509, 503 | date formatting |
| `etc/cosmopolitan/verify-ape.sh`, `build-ape.sh` | 82, 60 | nothing; low value alone |
| `tools/x2c-graph/tests/run.sh` | 947 | volume only |

## Rewrite on the compiler instead of translating

These tools contain a second parser for x2c source, written as regular
expressions, because they live outside the compiler. Translating them keeps
that parser. The port is a module over the `.xi` interfaces under
`builds/0` or `x2c translate --dump-ast` that exposes definitions, doc
comments, and spans, on which the tools' own logic is rewritten, the way
`tools/x2c-graph` already works.

| Tool | Lines | `re.` sites |
| --- | --- | --- |
| `agents/skills/find-redundant-validation/scripts/redundant_validation.py` | 1042 | 57 |
| `tools/x2c_source.py` (imported by six tools) | 1051 | 31 |
| `tools/audit-source-bloat.py` | 860 | 30 |
| `agents/skills/find-comment-slop/scripts/comment_slop.py` | 569 | 19 |
| `agents/skills/clean-x2c-source/scripts/source_style.py` | 385 | 15 |
| `tools/x2c_symbols.py` | 566 | 13 |
| `tools/gen-api-reference.py` | 1296 | 4, plus wrap and difflib |

`x2c_source.py` is the keystone: `gen-api-reference.py`,
`gen-module-catalog.py`, `repo-metrics.py`, `find-redundant-conversions.py`,
`audit-source-bloat.py`, and `redundant_validation.py` import it, so the
doc generators and the three skill analyzers move together. This is a
design, to be planned on its own before implementation.

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
  without an extension and executable; the older `tools/*.x` scripts keep
  their names.
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
  a Makefile or workflow line changes to call the script. The probe module
  replaces a prelude copied into seventeen shell files. No registry, cache,
  or second launch path is added.
- **Idiomatic.** Ports use `Job`, `Path`, `Args`, `Json`, `Regex`, and
  `Diff` as any script does; the compiler-backed rewrite reads `.xi` data
  through `List` and `Match` as `tools/x2c-graph` does.
- **Validators and fixtures.** None proposed beyond the CLI boundary case
  already landed for extensionless scripts.
