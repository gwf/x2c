# Header collection gaps

> Status: done, 2026-09-24. Gaps a-c landed on `dev` as `4aa8b0fe`,
> `440a6a98`, and `60303690`; gap d was a probe error. The yyjson header
> wiring step did not land; see "yyjson follow-up".
> History: found in raylib repair (PR #62). The corpus plan
> (`plans/archive/x2c-c-on-ramp-corpus.md`, f6f029f) and the 2026-09-17
> syntax cleanup fixed empty and storage-class prefix macros, attribute
> macro invocations, `_Noreturn`, and the guarded linkage group; `1956007c`
> fixed the leading `__attribute__` miscompile. Gary approved the scope and
> all three decisions on 2026-09-24.

## Result

Collecting a C header reads its unexpanded source (see "Host preprocessing"
in `docs/src/reference/language.md`). Collection now records the
declarations a C compiler sees for three more header forms.

## Delivered

| Gap | Before (`1aaf9479`) | Change | Fixture |
| --- | --- | --- | --- |
| a. `E void f(int);` with `E` defined where collection cannot see it | rows keyed `( void )` and `( int )`; with a named parameter, "missing closing parenthesis" | `src/parse.x:_prefix_macro_words` skips an unknown name before a builtin type word, qualifier, storage class, or `inline`, only while collecting a `.h` file (decision 1) | `c-unseen-prefix-macro`, whose `E` arrives through a computed include |
| b. `extern "C" {` / `#include` / `}` | "missing '}'" | `src/collect.x:_file` carries the open linkage count between segments; `Compiler.skip_linkage_brace` closes a group an earlier segment opened | `c-linkage-split` |
| c. `#include` in a branch C never compiles | parse errors from the skipped header, as in `uv/win.h` | `_file` tracks the conditional arms with `preproc_never_active_arm` (formerly `_never_active_arm`), which now also treats `_WIN32`, `_WIN64`, and `__CYGWIN__` as never defined off Windows (decision 2) | `c-false-arm-include` |
| d. yyjson struct body far from its typedef | the 2026-09-17 probe named `read_size`, not a member; `d.val_read` already emitted `->` | none | none |

Lost behavior: an `extern "C" {` in a collected header that is never closed
is no longer reported by x2c; the C compiler reports it. A `.x` unit's full
parse still reports it.

## yyjson follow-up

Passing `$(YYJSON_PREFIX)/include` to x2c with `-I` makes the five
`error->` sites in `packages/yyjson/src/yyjson.x` translate as `.`, but
`make -C packages/yyjson test` then fails in C: `conflicting types for
'yyjson_is_null'` and 19 more. `yyjson.h:419-440` defines
`bool unsigned char` in an `#elif` arm that C never takes (it includes
`<stdbool.h>`), collection records it, and the prototypes x2c emits for the
header's inline functions say `unsigned char`. Closing this needs a rule for
object-like definitions in arms collection cannot evaluate; that is a new
decision, so this step stayed out.

## Not in scope (decision 3)

- libuv (192 `->` sites) declares handle members through member-list macros
  in struct bodies (`uv/unix.h:98`); libcurl (9) puts an annotation macro
  after an enumerator (`curl.h:155`) and generates enumerators by macro.
  Both keep `->` on native handles.
- termbox2 (17), cstar (4), and torch (4) arrow sites were not measured.

## Plan review

- Facts: `_note_object_macro` records every visible definition, so a name
  absent from `object_macros` has none; gap a consumes that without a
  recheck. At a segment's end only linkage braces stay open, because every
  other file-scope form consumes its own. `preproc_conditional_kind` and
  `preproc_never_active_arm` already classify directives.
- Reuse: the prefix-word scan, `skip_linkage_brace`, the brace stack, and the
  existing segment loop in `_file`; no new traversal, cache, or
  representation. One `Compiler` field carries the linkage count.
- Idiom: direct parser skips over recorded facts, not a preprocessor.
- Validators and diagnostics: none added; one per-segment brace check moved
  to whole-unit collection. The three fixtures are positive.
