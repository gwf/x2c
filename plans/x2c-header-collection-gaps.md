# Header collection gaps

> Status: needs author scoping. Scope below is proposed, 2026-09-24, from
> probes at `1aaf9479` on `dev`; Gary has not approved it.
> History: found in raylib repair (PR #62). The corpus plan
> (`plans/archive/x2c-c-on-ramp-corpus.md`, f6f029f) and the 2026-09-17
> syntax cleanup fixed empty and storage-class prefix macros, attribute
> macro invocations, `_Noreturn`, and the guarded linkage group; `1956007c`
> fixed the leading `__attribute__` miscompile. The yyjson row below was a
> probe error and is closed.

## Result

Collecting a C header reads its unexpanded source (see "Host preprocessing"
in `docs/src/reference/language.md`). Collection should record the
declarations a C compiler sees for common header forms, so a package can put
its pinned upstream header on x2c's read path and write `.` on native
handles.

## Current gaps

Probes live in `/tmp/hg`; each unit is `#include "X.h"` plus a
`main(void)` that uses the declarations, run as
`builds/0/x2c translate --out-dir out X.x` (with `--dump-symbols` for a).

| Gap | Probe | Result at `1aaf9479` | Cause | Fix size |
| --- | --- | --- | --- | --- |
| a. Prefix name with no visible definition | `E void f(int);` `E int v;` | status 0; rows keyed `( void )` and `( int )` with type `( E )`, no `f` or `v`. With a named parameter, `E void f(int a);`, it fails: "missing closing parenthesis" | `src/parse.x`: `_prefix_macro_words` returns 0 for a name absent from `object_macros`, so `E` parses as a typedef name and `void` as the declarator | ~15 lines |
| b. Unguarded linkage group across an include | `extern "C" {` / `#include "inner.h"` / `}` | status 1, "missing '}'" | `src/collect.x:_file` splits the file into segments at each include; `_shallow_parse_loop` (`src/compiler.x`) runs `_check_unmatched_braces` per segment, so the `{` that `Compiler.skip_linkage_brace` opened is unmatched | ~15 lines |
| c. Include inside a false conditional | `#if defined(_WIN32)` / `#include "never.h"` / `#endif`, `never.h` holding `typedef BOOL (PASCAL *LPFN)(SOCKET s, PVOID p);` | status 1, "missing closing parenthesis" in `never.h`. Real header: `-I /opt/homebrew/include` on `uv.h` fails at `uv/win.h:129` | `src/collect.x:_file` follows every `#include` directive and ignores the conditional stack; `_scan_conditionals` hides only arms `_never_active_arm` classifies (`__cplusplus`, `_MSC_VER`, `#if 0`), and only tokens inside one segment | ~30 lines |
| d. yyjson struct body far from its typedef | real `yyjson.h` 0.12.0, `yyjson_doc *d; d.val_read` | works: emits `d -> val_read` | the 2026-09-17 probe used `d.read_size`, which is not a member of `struct yyjson_doc`, so `.` was correct | closed |

A garbage `never.h` such as `int @@@ bad;` does not fail, so a (c) probe
must hold a declaration the parser rejects.

Found while measuring package benefit, not in scope:

- e. libcurl 8.19 `curl.h:155`: an annotation macro after an enumerator,
  `CURLSSLBACKEND_NSS CURL_DEPRECATED(8.3.0, "") = 3,`, fails with
  "expected ','". With those removed from a copy, collection next fails at
  `curl.h:2456` ("invalid token", inside a comment, so the location is also
  wrong), and `CURLOPT(na, t, nu)` generates enumerators by expansion.
- f. libuv declares handle members through member-list macros
  (`UV_HANDLE_FIELDS`, `UV_REQ_FIELDS`, `UV_IO_PRIVATE_PLATFORM_FIELDS`
  inside struct bodies). With `uv/win.h` removed from a copy of `uv.h`,
  collection fails at `uv/unix.h:98` on `UV_IO_PRIVATE_PLATFORM_FIELDS`.
  `handle->data` (59 of libuv's sites) comes from such a macro, so fixing
  (c) does not unlock libuv. Expanding macros inside struct bodies is
  preprocessor work.

## Package `->` sites

Counted with `grep -rhoE '[A-Za-z_][A-Za-z0-9_]*->[A-Za-z_]+'` over each
package's `*.x` files at `1aaf9479`.

| Package | Sites | What unlocks them |
| --- | --- | --- |
| libuv | 192 | Not these gaps. About 60 are package test-state structs x2c already parses; about 25 are `sockaddr`/`addrinfo` members; the rest are libuv handles whose members come from member-list macros (f) |
| termbox2 | 17 | Reads its header already (8 remain after a local rewrite probe); the upstream `termbox2.h` is not cached here, so the rest is unmeasured |
| libcurl | 9 | Blocked by (e), not by a-c |
| yyjson | 5 | Nothing in the compiler: `packages/yyjson/Makefile` passes `$(YYJSON_PREFIX)/include` as `--c-include-dir` (C only). With it on x2c's path (`-I /opt/homebrew/include`, 0.12.0), all five `error->` sites translate as `.` today |
| cstar | 4 | `tools/cstar-verify.x`, not measured |
| torch | 4 | `callback_error->` in tests and examples, not measured |

## Decisions

1. **What collection records for a prefix name with no visible definition
   (gap a).** Recommendation: at the start of a file-scope declaration in a
   collected header, an identifier that is neither a recorded macro nor a
   visible type name, followed directly by a declaration specifier (a
   builtin type, qualifier, storage class, `struct`/`union`/`enum`, or a
   visible type name), is an empty prefix macro. Collection skips it and
   records `f` and `v` with their written types. Reason: two adjacent type
   names are never valid C, so the C compiler must see `E` expand to
   specifiers or attributes, and export macros (`API`, `EXTERN`, `E`) are
   the common case. The type is right for every expansion that is storage
   class, visibility, or attribute. The current behavior writes rows under
   `int` and `void`, which is corrupted state, and the alternative of
   recording nothing drops declarations the unit calls. The rule stays in
   collection (`c.shallow`); a `.x` unit's own source keeps rejecting an
   unknown name.
2. **Which conditional arms hide an `#include` (gap c).** Recommendation:
   reuse `_never_active_arm` for include directives in `_file`, and add to
   its never-defined set the platform macros of targets other than the one
   x2c was built for (`_WIN32`, `_WIN64`, `__CYGWIN__` on non-Windows
   builds). The alternative, evaluating `#if` against the host compiler's
   predefined macros, is a preprocessor evaluator plus a toolchain query and
   is larger than the benefit. Since libuv stays blocked by (f), Gary may
   instead defer (c).
3. **libuv and libcurl.** Recommendation: keep `->` on their native
   handles, as the style guide already says, and do not start member-list or
   enumerator macro expansion under this plan.

## Proposed scope

In order, as separate commits delivered directly to `dev`:

1. yyjson reads its pinned header: in `packages/yyjson/Makefile`, pass
   `$(YYJSON_PREFIX)/include` to x2c with `-I` instead of
   `--c-include-dir`, and write `.` at the five `error->` sites. Validate
   with `make -C packages/yyjson test`.
2. Gap a, per decision 1, in `_prefix_macro_words` or its caller in
   `src/parse.x`. Fixture: `c-unseen-prefix-macro` in
   `unittest/compiler-fixtures/`, style of `c-annotation-macro`, whose
   header declares `E void f(int a); E int v;` with `E` defined only on the
   C compile line, and whose unit calls `f(v)`.
3. Gap b: carry the linkage groups open at the end of one segment into the
   next segment of the same file in `src/collect.x:_file`, and check braces
   once at file end. Fixture: `c-linkage-unguarded-include`, style of
   `c-linkage-include`.
4. Gap c, only if decision 2 is accepted: track the conditional stack across
   the directive loop in `_file`, skip includes in hidden arms. Fixture:
   `c-false-arm-include`, whose false arm includes a header the parser
   rejects.

Out: gap e and gap f (preprocessor-scale expansion), libuv and libcurl
arrow removal, termbox2/cstar/torch arrow review (unmeasured; a later
package pass can use step 1's pattern). No new gate; the fixtures run in the
existing compiler-fixture suite. Each compiler commit ends with a review of
its authored diff, then `tools/gate-state.py ensure agent-pr-check`.

## Plan review

- Facts: `_note_object_macro` records every definition collection sees, so
  a name absent from `object_macros` and from the type table is known to
  have no visible definition; step 2 consumes that fact without rechecking
  it. `Compiler.skip_linkage_brace` and `c.braces` already track the open
  group; step 3 only moves where the unmatched check runs.
  `preproc_conditional_kind` and `_never_active_arm` already classify
  directives; step 4 applies them to includes.
- Reuse: `object_macros` and the prefix-word scan (`src/parse.x`),
  `skip_linkage_brace`, `_check_unmatched_braces`, `_never_active_arm`, and
  the existing segment loop in `_file`. No new traversal, cache, or
  representation. Step 1 is a flag change.
- Idiom: direct parser skips over recorded facts, not a preprocessor.
- Validators and diagnostics: none proposed. The three fixtures are positive
  and protect against wrong symbol rows (a) and rejected legal headers
  (b, c).
