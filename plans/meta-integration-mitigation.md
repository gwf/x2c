# Meta-integration mitigation

> Status: active - 2026-09-27. Repairs the confirmed findings of the
> expanded review of `meta-integration` at 1b23aaa7 (compared with `dev`
> at 472255ed). Work lands on `origin/meta-integration`; merging that
> branch into `dev` waits for this plan, a final-tree gate, and a quiet
> performance checkpoint. Opacity enforcement of project-meta results is
> withdrawn by Gary and is not part of this work.

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

## Deferred

The `stage.x`/`repl-lower.x` text decoding duplicate, helper builders
repeated from `lib/meta.x`, and the textual scanner in
`tools/gen-linked-meta.sh` remain review subjects. They cause no
reproduced defect and are outside this repair.

## Delivery

Workers branch from `origin/meta-integration`, build, run their
reproducers and affected tests, and return patches. The orchestrator
applies them to one integration branch, builds, reviews the combined
diff, runs `tools/gate-state.py ensure agent-pr-check`, and pushes to
`origin/meta-integration`. A quiet performance checkpoint under
`agents/performance-checkpoints.md` precedes any merge into `dev`.
