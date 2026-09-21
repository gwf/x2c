# Repository review remediation, 2026-09-18

> Status: done - remediation catalog archived 2026-09-20.
> Groups 1-9 landed on September 18; Gary's nine Group 10 decisions were
> recorded in 7948e686, with implementation through 2a20245c. Those decisions
> are [preserved below](#group-10-decided-2026-09-18), not pending approval.
> The original dbfc9cfc findings, corrections and validation remain below.

## Original status context

The following notes describe the implementation at the time of this plan.
Current disposition is the status above.

> remediation catalog for the whole-repository review at
> `dbfc9cfc`. Every row below was reproduced at that commit. `make verify`
> (918 suites), `make examples` (59), and `make check` (stages 0-3 identical
> across 178 C/H files) were all green there, so no current gate caught any
> of it. Groups 1-9 landed on 2026-09-18. Group 10 is not work; it records
> decisions that still need Gary, and the work added three more to it.
>
> Three rows did not survive contact and are corrected in place below: the
> `Thread.join` row in Group 1 was a misdiagnosis, Group 2's rule was
> narrowed after it regressed generated C, and Group 9's row 2 had the wrong
> cause. Each correction is recorded where the row is, not only here.

## Result

Nine fix changes, each owning files no other group touches, so groups can
proceed in separate sessions. Group 10 records the choices Gary subsequently decided. The original questions
and their answers are retained together.

A fix reproduces its row first, repairs the cause, and extends a test or
fixture only where the row is wrong output, a hang, a crash, or documented
behavior. The **R** column says who reproduced the row: `me` means the review
author ran the recorded probe at `dbfc9cfc`; `read` means the defect is
established by source that was read rather than run. Line numbers are from
`dbfc9cfc`.

Probes lived outside tracked source and are reconstructable from each row.

This catalog follows `plans/archive/repository-review-2026-09-17.md`, whose per-group
notes are accurate but whose top-level status header is stale: it lists
Groups 3, 4, 5, 7, 9, 11, 12, and 14-17 as open when the notes and the probes
below show them fixed. Correct that header as part of Group 7.

## Group 1: runtime locks and transfers

Files: `lib/pool.x`, `lib/thread.x`, `lib/process.x`, `lib/path.x`,
`unittest/test-pool.x`, `unittest/test-thread.x`.

These four share one cause: a resource released by a plain call rather than a
`defer`, on a path a shared `Error` cause can transfer past. Every shared
cause in `lib/error-macros.xmacro` transfers, so the release never runs.

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| `Pool.lookup` leaks a branch mutex on a raise; other threads hang forever. | Start a thread so `pool_multithreaded` is set, then `try { Pool.lookup(Pool.current(), void); } catch %(void-op *d): ...`, then start a second thread that calls `String.new` on a fresh spelling. The second thread never returns; killed at 10s. Without the `Pool.lookup` line the same program exits 0. | `pool.x:642-650` wraps `pool.table[key]` in plain `_lock`/`_unlock`, and `Map.get` (`map.x:202-203`) documents raising `<void-op>` for a void key or any cause from custom hashing and equality. Every other locked region in the file uses `defer _unlock`. Add `defer _unlock(pool)` in the loop body; `defer` in a loop body runs per iteration, including on `return` (verified). The mutex is recursive, so the raising thread never notices; the leaked lock is usually `value_root`'s, which every thread needs. | me |
| `Thread.join` destroys a successful worker result and aborts the process. | `Error.policy_set(<my-note>, <ignore>)`; a worker that calls `Error.raise(<my-note>, NULL)` and then returns 99. `join` raises `<join-fail>`, status 134. The same worker without the raise returns 99. | `_capture_errors` (`thread.x:113-118`) is an observing handler, so it fires for a resumable cause that dispatch resolves by policy and returns from. `thread.errors` is never cleared on the success path, and `thread.x:258` takes the error branch without exporting the result. The contract at `thread.x:17-19` says `<join-fail>` reports an error *escaping* the callback. Clear `thread.errors = void` as the last statement of the `try` body, after `thread.result = work.export(result)` succeeds - reaching that point means nothing escaped, and an export that raises still reaches the `catch`. | me |
| `Pool.retain_named` can raise while holding the storage mutex. | Not reproduced: needs `pool_multithreaded` set while `pool_storage_ready` is 0, which normal startup prevents. It becomes live from a `Pool.retain_named` reached after `_storage_shutdown` clears the flag (`pool.x:216`). | `pool.x:461-464` calls `_storage_initialize`, which calls `Scope.shutdown_hook`, which grows a registry and raises `<bad-arg>`, `<size-limit>`, or `<alloc-fail>`. `_storage_unlock()` is not deferred, so the mutex stays locked and every later `Pool.malloc`/`free`/`release`/`stats` blocks. This contradicts the invariant stated at `pool.x:152-153`. Use `defer _storage_unlock()`. | read |
| A pipeline stage that fails to spawn leaks the pipe read end. | `%((echo hi) (no-such-program) (cat)).job().status()`. `_spawn` raises `<not-found>` (`process.x:208`) for stage 1; that stage's `link[0]` is never closed. A catch-and-retry loop leaks one descriptor per attempt until `EMFILE`. | `process.x:253-261` gives `link[1]` a dedicated `defer _close(link[1])` but closes `link[0]` only via the next iteration's `previous` assignment. The function-level defer at `:228-232` closes the *previous* iteration's read end. Bring `link[0]` under the same block defer and clear it before the loop hands it on. | read |
| `Path.copy_file` uses an uninitialized `struct stat`. | Any `fstat` failure on the open source stream. The identity test then compares garbage `st_dev`/`st_ino`, which can make the copy return having silently done nothing, and `chmod(target, garbage & 07777)` can add or strip execute and setuid bits. `Path.copy_tree` (`:482`) funnels every regular file through it. | `path.x:453` discards `input.stat(&info)`; `File.stat` returns 0/-1 and raises nothing (`file.x:350`). `_open` ten lines earlier in the same file checks the same call before reading the struct. Check it and raise through `File.path_error` as the neighbouring failures do. | read |

**Outcome.** Four of the five landed. `Pool.lookup` took the fallback form:
over seven interleaved translations of `src/*.x` the per-iteration `defer`
cost 4.2% and one hoisted `defer` over a `Pool locked` variable cost 2.7%,
both above the ~1.4% noise floor, so the hoisted form is what shipped and the
measurement is recorded in its source comment. The pipeline row was upgraded
from `read` to reproduced - open descriptors grew 4, 5, 6, 7 over four
catch-and-retry attempts - and is now covered by
`process_failed_pipeline_closes_both_pipe_ends`, which reports 11 descriptors
against 3 without the repair.

**The `Thread.join` row was a misdiagnosis.** The repair above was applied,
changed nothing, and was reverted rather than landed as dead code. The
mechanism it assumed cannot happen: `_dispatch` walks handlers innermost
first, and `_run`'s bare `catch:` sits immediately outside `_capture_errors`
and always matches, so the observer firing means the cause did unwind out of
the callback. `<join-fail>` is therefore correct per `thread.x:17-19`.
Verified directly: a worker that raises under `<ignore>` never resumes, while
the identical raise on the main thread does. That difference is the real
finding, and it is Group 10 item 7.

## Group 2: volatile preservation across a transfer

Files: `src/cleanup.x`, `unittest/compiler-fixtures/volatile-indirect-write.x`
and its artifacts.

`43a559b7` preserves a local written through a pointer, but only for the
shapes `_preserve_pointee` can repair. C11 7.13.2.1 leaves a non-`volatile`
automatic modified between `sigsetjmp` and `siglongjmp` indeterminate.

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| A local written through a pointer handed to a callee gets no qualifier. | `static void store(int *slot, int value) { *slot = value; }` then `int a = 1; try { store(&a, 5); boom(); } catch %(bad-arg *d): ...`. Generated C is `int a = 1;` with no qualifier. | `_changed_operand` (`cleanup.x:241-252`) recognizes only assignment, compound, and postfix forms, so a call yields nothing, and `_collect_aliased` records `&a` only as the source of an assignment to a known holder. Inside a `try`, record the operand of every `&` that names a local directly into `preserved`, and add every direct-identifier call argument to `holders` so `_collect_aliased`'s existing resolution closes the `store(pa, 5)` variant too. Adding non-pointer identifiers to `holders` is harmless: `_collect_aliased` only matches `holder = &addressed`, which a non-pointer never forms. | me |
| A pointer declared without an initializer keeps an unqualified pointee. | `int a = 1; int *pa; pa = &a;` with `*pa = 5` inside a `try`: `a` becomes `volatile int` and `pa` stays `int *`. clang reports `-Wincompatible-pointer-types-discards-qualifiers`. | `_preserve_pointee` (`cleanup.x:511`) matches exactly one initialized single-level declarator. Have `_collect_aliased` also record the *holder* names it resolves to a preserved local, and let `_preserve_pointee` qualify a declaration when any declarator's name is in that set, not only when its initializer is `&preserved`. The block splitter at `:545-553` must split on the same condition, because C puts the qualifier on the whole declaration. | me |
| Two declarators in one declaration, and a multi-level pointer, take the same path. | `int *pa = &a, *pb = &b;` with both written through in a `try`; `int **pp = &p;`. | The same exact-arity pattern. Covered by the repair above once the set is the deciding input rather than the declarator shape. | read |

Over-qualifying is the accepted cost: a local whose address escapes into a
call cannot be proven safe, and this is what C requires a `setjmp`-using
program to assume. `src/regions.x` already treats raw stores, pointer
arithmetic, and callbacks as departures it will not track.

Residual limit to record in the source comment: a pointer assigned outside the
`try` and passed to a call inside it is closed by the `holders` extension, but
a pointer that reaches a callee through a struct field or an array element is
not. Say so rather than implying completeness.

**Outcome: the rule was narrowed, and the first row did not land.** The
address-escape widening was implemented and then dropped, because it regressed
generated C: a plain `foreach (Var v, items)` inside a `try` went from zero C
warnings to two, since the lowered cursor's address reaches `List_try_next`
and the cursor is now `volatile`. That is far too common an idiom to regress,
and the "over-qualifying is the accepted cost" line above was written about
the qualifier on the local, not about propagating one into every callee
signature. Silencing it would need a cast back to the unqualified type, and
casting away a declared qualifier is undefined per C11 6.7.3p6 - a diagnostic
traded for undefined behavior, which is worse.

What landed is rows 2 and 3: `_preserve_pointee` is replaced by a predicate
over the holder names `_collect_aliased` resolves to a preserved local, which
closes the uninitialized, multi-declarator, and multi-level pointer shapes and
*removes* an existing warning. The splitter also now splits before
qualification, fixing a separate leak found on the way: `int *twins = &twin,
*mates = &mate;` previously qualified both declarators.

The residual, recorded in the source with its reason: a local only a callee
writes through an address the body hands it is not qualified, because taking
its address already forces it to memory, so the register a transfer would
restore is not where its value lives. The formal C11 7.13.2.1 exposure remains
and is Group 10 item 8.

Fixture: `volatile-indirect-write.x` gained the uninitialized declarator and
the two-declarator case; `cleanup-loop-boundary`, `foreach-macro-lowering`,
and `exception-signal-mask` are byte-identical to `dbfc9cfc` again.

## Group 3: runtime value contracts

Files: `lib/list-generics.xmacro`, `lib/string.x`,
`unittest/test-typed-list.x`, `unittest/test-string.x`.

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| Typed-list `last` returns a plausible wrong value on nil while `car` returns zero. | `ListInt.last(NULL)` gives `-1`; `ListDbl.last(NULL)` gives a huge double. `ListInt.car(NULL)` gives 0. | `list-generics.xmacro:57` decodes `List.last`'s `void` (all-ones bits) through a raw mask. `car` at `:41` carries an explicit nil guard and a comment endorsing the drain-loop pattern this breaks. Give `last` the same `xs ?` guard returning `$zero`, and change its doc line from "in nonempty `xs`" to match `car`'s wording. Only `ListString` is safe today, because `Var.string` tag-checks. | me |
| `String.parse_char` accepts an octal escape above a byte. | `"'\\400'".parse_char()` returns 256. | `string.x:1322-1338` shares `_decode_escape_char` with `String.unescape`, which raises `<bad-arg>` above `\377` at `:1246-1249`. `parse_char` never raises and documents "one decoded byte" with "malformed and null input returns -1", so return -1 rather than adding a raise. Carried from the 2026-09-17 catalog, Group 19 row 5. | me |
| `String.new_fill` overflows `count + 1`. | `String.new_fill('x', INT_MAX)`. Signed overflow is undefined; at both `-O0` and `-O2` on this host it allocates a 2 GiB `String` rather than the documented refusal. | `string.x:409-415` is the only `String.malloc(n + 1)` site in the file that does not bound its length first. `String.pad` (`:893-897`) raises `<size-limit>` for exactly this. The doc comment already states the precondition; make it enforced, matching `String.pad`. | me |

Note for the implementer: the review's first report of this row claimed a
`memset` through NULL. That does not happen on this host; the defect is the
undefined overflow, not a null dereference.

## Group 4: compile-time Lisp SDK

Files: `etc/compiler-sdk.xlisp`, `unittest/test-system-macros.x`.

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| `x2c.type.members` rejects any enum initializer that is not a plain `int` literal. | `typedef enum Level { LOW = 1L, MID = 5 } Level;` with the `$member_table` macro from `unittest/test-system-macros.x:101`: "x2c.type.members found an unreadable member", note `(op = ("LOW") (expr (long) (literal (long) "1L")))`. `BIG = 3000000000` and `Q = P + 1` take the same path. | `_x2c.member` (`compiler-sdk.xlisp:65-68`) requires `(?value)`, a one-element initializer, which only `src/type.x:981-984` produces and only for `(expr (int) (literal ? ?value))`. `_integer_literal_type` returns `(long)`, `(unsigned)`, and so on for anything larger or suffixed. Read the initializer's spelling from the node rather than requiring a collapsed shape, so the book's promise at `docs/src/reference/language.md:1326-1328` - "the member's explicit initializer spelling", with only a non-enum `Type` rejected - holds. The existing unit test covers only `MID = 5`; add the suffixed and expression forms. | me |

The checked-in bootstrap reads `etc/compiler-sdk.xlisp` during stage 0, so
expect the two-round bootstrap refresh: the first `precommit` can fail
`stage-diff-0` until `bootstrap/` is regenerated. That is the documented
publication path, not a defect.

## Group 5: gate holes

Files: `unittest/probes/run-raw-symbol-sweep.sh`,
`unittest/probes/run-cli-boundary.sh`,
`unittest/probes/run-preprocessor-boundary.sh`,
`unittest/compiler-fixtures/run.sh`, `tools/gate-state.py`, `Makefile`,
`etc/build-config.mk`, `.gitignore`.

None of these adds a gate or lengthens one; each closes a hole in a check that
already runs, so the process ceiling in `AGENTS.md` is not engaged.

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| `proof-raw-symbols` scores green when its workers never run. | An `xargs` that exits before spawning - a child exiting 255, or the worker script losing its execute bit, which makes `xargs` exit 126/127 - leaves `$BUILD/failed` empty after the `rm -rf` at `:59`, so `[ "$failures" -eq 0 ]` passes for units never compared. | `run-raw-symbol-sweep.sh:123-132` fans out with `xargs ... \|\| true` and counts *failure markers* with no positive per-source receipt. It is the only gated proof built on negative markers; the fixture runner and `examples/check.sh` both use positive tallies. Have the `--one` worker write `$BUILD/done/$key` on success and have the parent require that count to equal `required`. Keep the failure markers for their messages. It is inside `agent-pr-check`. | read |
| Two negative probe assertions can never fail. | A bare `! cmd \| cmd` statement is exempt from `set -e`; verified directly (`! echo hello \| grep -q hello` does not stop a `set -euo pipefail` script, which then exits 0). | `run-cli-boundary.sh:1079` asserts that an `-O0` override drops `-O2`; `run-preprocessor-boundary.sh:132` asserts no default `-O`/`-g` leaks. Neither script defines a `fail` helper, so rewrite each as an explicit `if ... then echo >&2; exit 1; fi`. The 2026-09-17 catalog recorded these two as "inside conditions and are fine", which is wrong; the `run-header-cache.sh` forms it grouped with them really are safe, because they end in `\|\| fail`. | me |
| `verify-fixtures` can read a stale tally. | `unittest/compiler-fixtures/run.sh:17` is `mkdir -p "$build"` with no `rm -rf`. The stale-tally guard lives in the child (`rm -rf "$case_build"`), so it fires only for fixtures whose child started. An `xargs` that aborts partway leaves every unstarted fixture's tally from the last green run, and `:311-318` reads it as a pass. | Masked inside `agent-pr-check`, because `verify` runs `$(MAKE) -C unittest clean` first (`Makefile:79`). Not masked for `make verify-fixtures` (`Makefile:192-193`) or `make -C unittest compiler-fixtures`, which `AGENTS.md` and `unittest/AGENTS.md` both present as the fixture check. Add `rm -rf "$build"` as `run-raw-symbol-sweep.sh:59` does. | read |
| `gate-state.py` records no `X2C_HOME`, though the compiler reads it. | Run `agent-pr-check` with `X2C_HOME` pointing at an installed toolchain, then `gate-state.py check agent-pr-check` in a clean shell: `valid`, for a tree never proven under the repo's own SDK. | `tools/gate-state.py:53-62`. `src/utils.x:29` resolves the compiler home from `X2C_HOME`, which changes where `etc/compiler-sdk.xlisp` and the prelude interfaces come from, so it changes translation output. Add `X2C_HOME` to `TOOL_ENV_VARIABLES`. Do not add `HOME` or `TMPDIR`: they vary per session and do not change output, so recording them would make evidence spuriously stale. | read |
| `make debug` rewrites a tracked file. | `Makefile:465` -> `config-debug` -> `Makefile:415` writes `etc/build-mode`, which `git ls-files` tracks. The worktree goes dirty, and gate evidence goes stale. | Keep `etc/build-mode` tracked as the committed default and have `config-debug`/`config-optimize` write `etc/build-mode.local`, which `etc/build-config.mk` prefers when present and `.gitignore` excludes. Carried from the 2026-09-17 catalog, Group 13. | me |

## Group 6: the API reference's dangling section

Files: `tools/gen-api-reference.py`, `docs/src/library/modules/index.md`
(regenerated).

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| The book tells readers that 86 working APIs will not link. | `docs/src/library/modules/index.md:98-101` heads "Declared but not defined" with "Calling one fails at link time". A program calling `File.close`, `Array.len`, `Array.capacity`, `Array.truth`, and `String.c_len` - five entries drawn from four of the section's receivers - compiles, links, and runs. `File.close` is a foreign alias at `lib/file.x:31` that `lib/file.x:226` and the exceptions chapter both call. | `unmatched` (`gen-api-reference.py:728-747`) derives "defined" from a source-text scan that recognizes neither foreign protocol aliases nor macro-generated family members. Delete the section and the `DANGLING`/`unmatched` machinery. The question it asks is already answered by every gate that compiles `lib/`, by `proof-raw-symbols`, and by the link step itself the moment anything calls a genuinely missing prototype; the unit interfaces own what a unit publishes. A published claim that has never been right about any sampled entry does not earn its keep. | me |

## Group 7: documentation accuracy

Files: `docs/src/reference/cli.md`, `docs/src/guide/collections.md`,
`docs/src/guide/regions.md`, `agents/x2c-philosophy.md`,
`agents/x2c-coding-style-guide.md`, `agents/logger-and-diagnostics-guide.md`,
`agents/adapters-macros-decorators.md`, `agents/x2c-debugging-guide.md`,
`packages/README.md`, `packages/cstar/README.md`, `site/src/pages/index.astro`,
`plans/archive/repository-review-2026-09-17.md`.

| Defect | Cause and repair | R |
| --- | --- | --- |
| `cli.md:585` says five codes are reported as warnings; there are six. | `src/macros.x:868` reports `<macro>` at warning severity from `x2c.diagnostic.warn`, added by `9f1b5b52` and documented as user-reachable at `language.md:1330`. Add the row; `cli.md:620-623`'s "a category with both severities" list is also incomplete. | me |
| `agents/x2c-philosophy.md:118,670` and `agents/x2c-coding-style-guide.md:419,430` name `String.pool_retain`, `pool_retain_named`, and `String.pool_release`. | None exists anywhere in `src/` or `lib/`; the owners are `Pool.retain_named` (`pool.x:461`), `Pool.retain` (`:510`), `Pool.release` (`:519`). The style guide's "prefer" exemplar shows code that does not compile. | me |
| `agents/x2c-philosophy.md:709` and `agents/x2c-debugging-guide.md:82-83` say the compiler records one ordinary error by default. | `src/cli.x:1002` sets `max_errors = 20`, applied at `src/frontend.x:224`. The book is right (`cli.md:569`), and `agents/logger-and-diagnostics-guide.md:140-142` is right about the bare `Compiler.new` default of 1 that the frontend overwrites. | read |
| `agents/logger-and-diagnostics-guide.md:109-117` omits the `severity` field. | `src/diagnostics.x:124,133-138` always carry it, and `agents/x2c-docs-drift-report.md:60-61` names this guide the contract's owner. A consumer built from the table drops the field that separates errors from warnings. | read |
| `agents/adapters-macros-decorators.md:559-571` says cast, statement, and declaration construction stay private. | They are public: `etc/compiler-sdk.xlisp:49,50,55,58`, documented at `language.md:1250-1252`. The same file's `:110-113,508-529` rests on a `Type` surface `src/type.x:197-203` no longer has, and `:326-327` names `_build_mkdirs`/`_build_remove_tree`, both deleted. | read |
| `agents/x2c-philosophy.md:629-631` says the volatile pass qualifies directly modified locals. | `src/cleanup.x:435-453` also preserves locals written through a held pointer, which `language.md:2652-2655` already records. Group 2 widens this again; update both together. | read |
| `collections.md:1159,1200,1204` say three packed `Map`s and `:932-934` say six `Array`s. | `lib/typed-map.x:68` declares a fourth, `MapStringInt`, with its own Var tag and a String-key re-canonicalizing export; `lib/typed-array.x:59,159-160` declares a seventh, `ArrayString`, which `protocols.md:93` already references. | read |
| `regions.md:21` says the pass exempts three ways of leaving a region. | `src/regions.x:116` also exempts the promote family, which `memory.md:436` states. Group 8 changes which names that row holds; land them in either order but check the count after. | read |
| `cli.md:555` omits `-framework`, and `-pthread` is undocumented. | Both are live rows in `src/cli.x`. | read |
| `packages/README.md:88-90,135-137` say three packages carry a Lisp surface. | Five Makefiles define `lisp-example`; sqlite and torch also document `SqliteLisp.install` and `TorchLisp.install`. `packages/cstar/README.md:18` links `../../plans/x2c-cstar-verification.md`, which is in `plans/archive/`. | read |
| "Builds are currently tested on macOS" in `site/src/pages/index.astro:238` and `packages/README.md:6`. | `.github/workflows/release.yml:66-73` builds six package bundles across `macos-15`, `macos-15-intel`, `ubuntu-24.04`, and `ubuntu-24.04-arm`. | read |
| `plans/archive/repository-review-2026-09-17.md`'s status header is stale. | It lists Groups 3, 4, 5, 7, 9, 11, 12, and 14-17 as open; the per-group notes say fixed, and both `_Generic` rows and the indirect-write `volatile` row were confirmed fixed at `dbfc9cfc`. Rewrite the header to match the notes and to name the rows this catalog carries forward. | me |

`tools/check-docs.py:14-20` scopes link checking to `README.md`, `AGENTS.md`,
non-recursive `agents/*.md`, `docs/*.md`, and `docs/src/**`, so
`agents/skills/**`, `plans/**`, `packages/**`, and `site/**` are unchecked -
which is where the one dead link sits - and `:135` strips the fragment before
resolving, so no book anchor is validated. Widening that scope is a gate
change; see Group 10.

## Group 8: the region runtime table

Files: `src/regions.x`.

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| Two rows name functions that do not exist, and the real sibling is missing. | `Map_free` (`regions.x:105`) and `Var_promote` (`:116`) appear nowhere in `bootstrap/`, `lib/`, `src/`, `unittest/`, or `tools/` outside this table. The real Map teardown is `Map_cleanup`, already present, and there is no `Var.promote`. `Atom_promote` is a real public entry point (`bootstrap/lib/atom.h:9`, `lib/atom.x:26`) and is absent from the `(exit)` set its two siblings occupy. | Delete the two dead rows and add `Atom_promote` to `(exit)`. Observed consequence today is nil, because Atoms are not born in the `(alloc)`/`(pool)` set, so this is dead machinery plus an unexplained sibling gap rather than a live miscompile. Check `regions.md:21`'s count afterwards; Group 7 owns that line. | me |

## Group 9: rows carried from the 2026-09-17 catalog

Files: the match engine and `lib/list.x` (row 1), `lib/scan.x` (row 2),
`etc/init.xlisp` (row 3).

| Defect | Reproduction | Cause and repair | R |
| --- | --- | --- | --- |
| A bare-binder template left unbound by a successful match aborts. | `%(outer (b)).search_replace(%(!or (a *x) (b)), <"*x">)` raises `<void-op>` from `List.cons` and exits 134 through the error floor. | `_apply_capture_template` and the reference's `bindings.assoc(template)`. An `!or` alternative that matches without binding the other alternative's binder must substitute the same value `try_match_replace` writes for that input rather than raising. Catalog Group 20 row 1. | me |
| A raw `0xFF` byte in code position ends tokenization. | `undeclared_\xff = 1;` gives "unexpected end of file" pointing at the byte. | **The stated cause was wrong.** There is no `char`/`EOF` comparison in `lib/scan.x`, and 0xFF is not special - a backtick, 0x80 and 0xFE all gave the same message. A lexical failure appends zero-width `<error>` and `<eof>` tokens, nothing reports the `<error>`, and the parser blames the `<eof>`. `Compiler.tokenize` now reports the `<error>` as `parse: invalid token` when the tokenizer status is `<malformed>`, while `<incomplete>` keeps "unexpected end of file". Fixed; `unknown-character.x` pins it, and `inactive-arm-lexical-error` stopped emitting a nonsense `type: expected scalar type`. | me |
| `binder?` misses binders of ten or more characters. | `(binder? '?abcdefghi)` is true; `(binder? '?abcdefghij)` is false, because `symbol?` is false for a spelling that does not fit a compact `Symbol`. A `match-case` clause using such a binder fails the build with `(unbound (name ?abcdefghij))`. | Fixed in `binder?` alone: `(or (symbol? value) (eq? (type value) 'lsym))`. `symbol?` itself was deliberately **not** widened - it has three other callers, including `x2c.literal.symbol`, which would then emit a wrong Symbol literal for a long atom. Proven: `etc/init.xlisp` is read from `root_dir` at translate time rather than compiled into bootstrap C, and stages 0, 1 and 2 stayed byte-identical across 178 generated C/H files. Why the AST-to-Lisp spike's own fix broke that spike was **not** established - its sources were uncommitted in a worktree that no longer exists - so the widened-`symbol?` explanation above is a supported hypothesis, not proof. | me |

## Group 10: decided 2026-09-18

Gary ruled on all nine on 2026-09-18; `a627b8ac..2a20245c` carries the work.

1 not gated, recorded in `agents/README.md`. 2 done - `cc-stderr` is a
compared sidecar. 3 both kept and added to the quick-start; `./configure` is
live and `test-configure.py` is its only coverage, so the earlier
delete recommendation was wrong. 4 left silent. 5 fixed rather than
documented: `$time` reports from a `defer`, which also covers an error
transfer, and the rule is in the language reference. 6 widened to
`agents/skills`, `plans`, and `packages`; `site` stays with `site-check`,
whose links are rendered URLs. 7 fixed - see below. 8 kept as shipped. 9 both
kept: they are two of seven no-status wrappers with no production caller, so
removing only these would be arbitrary.

Item 7 had a second cause neither the review nor the plan saw: the policy
table is per-thread, so `Error.policy_set` never reached a worker at all.
Workers now inherit the starting thread's policy, and the backstop declines
unless the policy is `<abort>`. That is a public `Thread` semantics change.

Comparing `cc.stderr` immediately earned its keep: it caught
`map-generator-family` still declaring `Scope *scope` where `16ab9663`
changed the field to `Scope scope` that morning, which was generating
type-incorrect C. Seven more warning sources are recorded as expectations and
listed as open defects for follow-up, the `class-runtime` const-class `_free`
being the only other compiler-side one.

The original nine items follow, for the record.

1. **`tools/x2c-graph` is compiled and tested by no gate.** Nothing in the
   Makefile, the workflows, `unittest/`, or `tools/` references it, though
   `AGENTS.md` routes tool changes to `agent-pr-check` and `plan-x2c-change`,
   `review-x2c-repo`, and `simplify-x2c-source` all direct agents to run it.
   Its own `make test` passes today. Gating it is a recurring cost the
   process ceiling reserves to you; the alternative is to say in
   `agents/README.md` that the tool is ungated and may not build.
2. **Twelve fixture `cc.stderr` files hold C warnings no check reads.** Group 2
   removes two sources of them. Whether the fixture runner should compare
   `cc.stderr` at all is a gate question.
3. **`make build-recovery` and `tools/test-configure.py` are orphaned.**
   `build-recovery` is in `VERIFY_TARGETS` and `make help` but no gate,
   workflow, or quick-start table runs it; `test-configure.py` is referenced
   nowhere. Run them, or delete them.
4. **`class Color;` produces no registration and no diagnostic.** It is the
   documented forward form, so silence may be intended. If it is not, the
   decorator in `etc/builtin-macros.xmacro` should say so.
5. **A `Statement` decorator on a function body silently drops its trailing
   work.** `$time("work") static int work(int n) { return n * 2; }` compiles
   and runs, and the timing line never prints, because the body's `return`
   leaves before the stop clock. The book at `language.md:975` describes the
   feature without this limit. Document the limit, or reject a decorator whose
   production has code after the body.
6. **`tools/check-docs.py` checks no anchors and skips `agents/skills/**`,
   `plans/**`, `packages/**`, and `site/**`.** Widening it is a gate change.
7. **A resumable policy resumes on the main thread and not inside a worker.**
   `Error.policy_set(<my-note>, <ignore>)` then `Error.raise` returns on the
   main thread; the identical raise inside a `Thread` callback never resumes,
   because `_run`'s bare `catch:` always matches and turns it into
   `<join-fail>`, discarding the worker's result. `Error.policy_set` documents
   no such limit. Making them agree means changing how `Thread` catches, which
   is a public `Thread` semantics change.
8. **A local only a callee writes is left unqualified across a transfer.**
   See Group 2's outcome. The two available repairs are a C11 7.13.2.1
   exposure that is mitigated in practice, or a warning on every such call
   whose only cure is undefined behavior. Group 2 shipped the first.
9. **Two scanners lost their last in-repo caller.** `scan_c_string` and
   `scan_block_comment` in `lib/scan.x` are public API with no remaining
   caller after Group 9 row 2. Keep or remove.

## Validation

Each group reproduces its rows first, then repairs, then verifies:

- Groups 1 and 3: `make verify`, plus the named suites through
  `(cd unittest && ./test-all pool_suite thread_suite typed_list_suite
  string_suite)`.
- Group 2: `make verify-fixtures`, then `make verify-fixtures-update` once the
  generated C is reviewed.
- Group 4: `make verify`; expect the second bootstrap round at publication.
- Group 5: run each repaired probe directly and confirm it now fails on an
  introduced regression before restoring it.
- Groups 6 and 7: `make doc-check` and `make doc-generate`, reviewing the
  regenerated artifacts.
- Groups 8 and 9: `make verify`, and for row 3 a full bootstrap round.

Final tree: `tools/gate-state.py ensure agent-pr-check` for Groups 1-6 and
8-9; `tools/gate-state.py ensure doc-check` for Group 7 if it lands alone.

**As landed**, all nine groups were integrated into one tree, `bootstrap/` was
regenerated once across them rather than nine times, and the tree was gated
once. `make verify` reports 920 tests and 719 fixtures against the 918/719
baseline. `make packages-check` was not run; Group 9 row 3 touches shared
compile-time Lisp, which is the one surface a package client could see.

## Plan review

**Facts the producers establish, and whether a consumer rechecks them.** Group
1 adds no checks; it moves existing releases onto `defer`, which is the
mechanism the same files already use, and deletes nothing a producer proves.
Group 3's `String.new_fill` bound is the one place the plan adds a check: it
guards an undefined signed overflow the caller cannot be trusted to avoid and
that no producer rules out, and it matches `String.pad`'s existing
`<size-limit>`. The typed-list `last` guard is not a new check but the removal
of an asymmetry with `car` in the same macro. `String.parse_char` gains no
raise; it returns the -1 its own documented contract already promises.

**What the design deletes or reuses.** Group 6 deletes the `DANGLING` set,
`unmatched`, and a published book section - the largest single deletion here,
and the correct answer, because the claim was never true of any sampled entry
and the link step already owns the question. Group 8 deletes two dead table
rows. Group 2 adds no new representation: it widens two existing collectors and
threads one additional set through machinery that already exists, rather than
introducing a pointer-alias analysis. Group 5's positive receipt reuses the
tally idiom the fixture runner and `examples/check.sh` already use, and adds no
target, so it does not touch the process ceiling.

**Why the source stays idiomatic x2c.** Every repair is the local form the
surrounding file already uses: `defer` for a release that a transfer can skip,
a nil guard matching the sibling operation, an explicit `if ... exit 1` in
scripts that define no `fail` helper, and the `.local` override pattern for a
build mode that must not dirty a tracked file. No group introduces a framework,
a second validator, or a parallel implementation.

**Validators, dedicated diagnostics, and negative fixtures.** One validator:
`String.new_fill`'s `<size-limit>`, protecting undefined behavior in a public
constructor. No new dedicated diagnostics. No negative fixtures. Group 2
extends one existing fixture with two positive shapes whose current output is
wrong C; Groups 1, 3, and 4 extend existing suites with cases that today
produce a hang, a lost result, a wrong value, and a rejected build. Group 10's
open items are deliberately not implemented, because each one either adds a
recurring gate or changes public behavior.

The last implementation step in every group is a review of the completed
authored diff - for trusted facts rechecked, code that could be deleted or
reused, and machinery that does not earn its keep - with fixes applied before
publication validation.
