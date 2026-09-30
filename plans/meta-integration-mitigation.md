# Meta-integration mitigation

> Status: reference -- integration repairs are present on verified dev
> cfd8324c (2026-09-30). The original 2026-09-27 results follow.
> The review findings R1-R12 and the
> documentation items are repaired on `origin/meta-integration` at 4bb59cc3.
> `agent-pr-check` is green there, and CI `check.yml` with release
> validation and the Windows probe passes all 12 jobs (run 36342464030).
> APE and Cosmopolitan were removed on the same branch
> ([archive/remove-ape.md](archive/remove-ape.md)). Optional checks that
> also failed on `dev` were repaired; see "Optional checks" below. Opacity
> enforcement of project-meta results is withdrawn by Gary.
>
> Original pre-merge discussion: Gary's decision on the stage 3 build
> time (about 15% slower than `dev` on a loaded host; already present at
> 1b23aaa7, and the mitigation adds no measurable build cost). The
> follow-ups listed below remain recorded; this is not a current merge block.

## Goal

Keep the native backend reuse and the REPL extraction. Repair each
confirmed defect at its shared cause, so the branch stops producing
wrong values, failing installed projects, or crashing where `dev`
reported a catchable error. Each repair gets one regression test from its
review reproducer, in the existing fixture or unit suites. No recurring
gate, per-function compilation, generic framework, or opacity mechanism
is added.

## Work items

Items that share files run in one worker. The reproducers named in the
review live under `/tmp` on Gary's host.

### A. Argument evaluation (`src/stage.x`)

R1. Remove the unwrap of any one-argument `String` call at
`src/stage.x:105-106`. Only an actual identity conversion may fold; an
ordinary call such as `change("original")` must run or be rejected as
`dev` rejects it. Reproducer: `/tmp/x2c-meta-review-linked/string-call.x`.

### B. Linked functions and meta installation (`src/macros.x`)

R2. Linked-function selection (`src/macros.x:1931-1934`) must include
the identities of the callees frozen into the linked code. Compute the
key over the function and its transitive linked dependencies, so a
changed callee makes the linked copy ineligible. Reproducer:
`/tmp/x2c-meta-review-linked/probe.x` prints `123 0 0`, where the
candidate prints `123 1 0`.

R3. A meta definition imported through an included header must stay
callable. Install the staged `Func` with the owning `Lisp.bind` instead
of borrowing `Lisp.set_global` (`src/macros.x:2197`), then confirm the
disposal chain. Reproducer: `/tmp/x2c-stage-review/normal.x`,
`bridge.x`, `defs.xmacro`.

### C. Project meta build (`src/meta-project.x`, `etc/x2c-payload.x`)

R4. The support payload copies `etc/meta-helper.x`.

R6. Meta discovery reuses ordinary collection's include parsing and
resolution (including whitespace and `-I`) instead of the literal
spelling at `src/meta-project.x:107-111`.

R7. A failed helper build is never reused as a cached result. Retain
failures only until any input, including an include that was missing,
could have changed; the simplest correct policy is not to cache failure.

R10. Host helper compilation drops target architecture and ABI flags
(`--target`, `-arch`, `-m*` ABI selections, `--sysroot` for the target)
from `cc_args`, keeping include and macro inputs
(`src/meta-project.x:395-397`). The group object is built for the host.

### D. Compiler-linked extensions (`src/meta-project.x` link step)

R5. The helper links the exact extension implementation compiled into
the compiler. Resolve how that object or archive reaches the helper link
(`src/meta-project.x:326`) without substituting current package source.
Reproducer: `bash unittest/probes/run-native-modules.sh`. If no correct
route exists within this plan's size limit, stop and report to Gary;
withdrawing the capability is his decision.

### E. Meta static reset (`etc/meta-helper.x`)

R9. A reset failure (`etc/meta-helper.x:319-320`) is reported at the
requesting `$` call. Translation fails. Reproducer:
`/tmp/x2c-stage-extra/reset.x`.

### F. Lisp capacity and safety (`lib/lisp-init.x`, `etc/init.xlisp`, `lib/lisp.x`)

R8. Native `append` copies iteratively, preserving argument checks and
sharing of the final tail. Reproducer: `/tmp/meta-review-append.x` with
300,000 elements raises nothing or a catchable error, never SIGSEGV.

R11. `map` and `filter` in `etc/init.xlisp:160-170` accumulate and
reverse (or use existing iterative list operations), so 4,000 elements
succeed. Reproducer: `/tmp/meta-review-lists.x`.

R12. The evaluator stack guard (`lib/lisp.x:1488`) derives its allowance
from the running thread's actual stack size where the platform reports
it, falling back to a conservative bound. Reproducer:
`/tmp/meta-review-smallstack.x` at 4096 KiB catches `call-stack`.

### G. Documentation and workflow

- Mark the opacity item in `plans/native-meta-execution.md` withdrawn,
  give that plan one current status, and add it and this plan to the
  plans index.
- Update the language reference's meta execution account to the native
  path, with the accepted compatibility changes.
- Remove the word-machine benchmark descriptions in
  `docs/src/internals/reference-lisp.md:165,178`.
- Document `X2C_META_TIMEOUT` in the CLI reference, the scalar
  session-global address limit in the REPL guide, and an old-to-new
  autodiff import note. Fix the REPL `--dump` help text.
- S10: generated `src/linked-meta.x` counts as generated output in gate
  source-change detection, like `lib/x2c.x`.

## Optional checks

Every check below failed on `dev` at 472255ed and passes on the branch.

- The sanitizer script and the termbox2 test rule link `match-recursive`;
  `unittest/test-var.x` destroys its Lisp session (Linux leak check).
- `<errno>` Symbols are quoted as `<"errno">` in `src/` and four unit
  tests, because CPP symbol mode expanded glibc's `errno` macro.
- The CLI boundary probe compiles its no-`PATH` case to an object.
- Compile-time floating results are spelled by `_meta_hex_float` in
  `src/stage.x` instead of host-dependent `%La`.
- `lib/lisp.x` no longer exposes `json.x` and `diff.x` to every unit; their
  native targets moved to the optional `lib/lisp-targets.x`. `process.x`
  is included privately. This repaired yyjson, libcurl, and the
  `mandelbrot` example.
- `tools/check-doc-examples` finds headers under symlinked package `deps`.

## Follow-ups

None blocks the merge into `dev`.

- **Header import replay.** A cached header replays its declarations but
  not its `$(import ...)` effects. The R3 repair works around this by
  forgetting collection-cache entries after the helper build, which two
  unrelated edits broke on a cold cache. Replaying imports would remove
  that workaround and the `slot` flag in `_evaluate_meta_value`, and would
  fix two units that include one bridging header (also failing on `dev`).
- **`meta` functions shared through an included `.x` header.** They are
  not installed in the including unit, on `dev` as well. Sharing requires
  a `.xmacro` today. Fixing it follows from the replay repair.
- **Retire `meta native`.** With every `meta` body native, the marker only
  selects the compiler's linked copy. The linked-copy hash check that
  `src/linked-meta.x` applies to shipped `.xmacro` code could cover
  `lib/` too, leaving the bodyless prototype for functions without an x2c
  body.
- **Private includes reach includers.** A `#pragma private` include
  still replays into every unit that includes the module. `lib/lisp.x`
  therefore still exposes `regex.x`, `typed-array.x`, and `typed-map.x`,
  and `Job` from `process.x`, to x2c code. Changing the rule is a
  language decision for Gary.
- **C macro names in CPP symbol mode.** Quoting fixed only `errno`; any
  Symbol whose name is a C macro can still be expanded.
- **`Path.glob` and symlinked directories.** It does not descend into a
  symlinked directory named by the pattern, unlike a shell glob.
- **Compiler under ASan.** The sanitizer runs the runtime and unit tests,
  not the compiler binary on meta fixtures.
- **Stage 3 build time.** Measure `dev` and the branch on a quiet host and
  find where the branch's build time goes.
- **R5 archive distribution.** `make install` does not copy the
  `<compiler>.extensions` archive, so an installed compiler built with
  extensions cannot link them into its helper.
- **R10 host flags.** `_meta_host_args` filters target flags by a deny
  list; separate host and target inputs would remove the guess.
- **Merge readiness.** `origin/dev` has advanced (171bec53); the merge
  needs a final integration, the gate, and a CI run, after Gary's stage 3
  decision.
- **REPL suspected removals (about 250-270 lines, unproven).** Decline by
  raising once instead of about 80 return-value checks in
  `repl-lower.x`; bind natives directly and drop the alias layer in
  `repl-runtime.xlisp` (needs timing); replace the hand-written buffers
  and history in `repl-input.x` with `lib/buffer.x` and an Array; review
  the terminal width fallback.
- **REPL coverage.** The REPL tests never run lowering paths a user can
  reach: `&x`, `x[i] = v`, string templates, `if`, arrays, and
  destructuring. Add them before a larger REPL refactor.
- **REPL partial state.** A failed submission leaves its partial effects
  in the session.
- **REPL piped runaway.** Without Ctrl-C, a runaway loop on piped input
  runs about 50 s before the 40M-call budget stops it.
- **Match machine.** Fix the stale "shared wordcode" comment at
  `lib/match.x:16` and the `MatchFrame` comment about Lisp frames.
  Replacing the `MatchCache` LRU, leases, and generations with a plain
  plan table is a separate measured change (hit <= 1.1x, cold <= 1.3x).
- **Native-meta consolidation table.** About 8 rows of the "Also strip or
  consolidate" table in [native-meta-execution.md](native-meta-execution.md)
  are not started: `SymTxn` copy-on-begin, `convert_expression`, the
  `<macro-expr>` resolver sites, diagnostics renderers, the error-record
  Pool merge, `lisp-values` derivable rows, and the small public-surface
  drops.
- **Lint.** About 1,900 candidate findings remain tree-wide, and files
  outside this branch have had no violation pass. `silent-shape-guard`
  treats any `.len()` as a shape test and is too noisy to act on.
- **Bootstrap refresh pruning.** `make bootstrap-refresh` copies generated
  files over `bootstrap/` without deleting ones whose source was removed;
  `bootstrap/src/bootstrap.[ch]` had to be removed by hand.
- **Install coverage.** `run-meta-cache-key.sh` builds its home with `cp`
  since the payload `support` mode was removed, so no probe notices if
  `make install` stops shipping `etc/meta-helper.x`.
- **Review duplicates.** The `stage.x`/`repl-lower.x` text decoding, the
  helper builders repeated from `lib/meta.x`, and the textual scanner in
  `tools/gen-linked-meta.sh` remain review subjects without a reproduced
  defect.

## Delivery

Workers branch from `origin/meta-integration`, build, run their
reproducers and affected tests, and return patches. The orchestrator
applies them to one integration branch, builds, reviews the combined
diff, runs `tools/gate-state.py ensure agent-pr-check`, and pushes to
`origin/meta-integration`. A quiet performance checkpoint under
`agents/performance-checkpoints.md` precedes any merge into `dev`.
