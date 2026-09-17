# Header collection gaps

> Status: needs author scoping - 2026-09-16, rows re-reproduced 2026-09-17.
> Found while repairing raylib collection in PR #62. The corpus work in
> `plans/archive/x2c-c-on-ramp-corpus.md` (f6f029f) fixed the empty and
> storage-class prefix macros, macros among parameters, and the
> `__cplusplus`-guarded linkage group. The five forms below still fail. No
> package build hits them today.

## Result

Collecting a C header reads its unexpanded source (see "Host preprocessing"
in `docs/src/reference/language.md`). Collection should record the same
declarations and types a C compiler sees for these forms, and a unit should
accept the C11 forms among them.

## Reproduced gaps

Each row was translated with `builds/0/x2c translate` at 63d8c1b from a unit
that includes a header holding the form and calls `f`; the symbol table was
read with `--dump-symbols`.

| Header form | Result |
| --- | --- |
| `#define ATTR(x)` or `#define ATTR(x) __attribute__((deprecated))`, then `ATTR(1) void f(int a);`, as libcurl's `CURL_DEPRECATED(...)` at `curl.h:157` | "missing closing parenthesis" |
| `__attribute__((visibility("default"))) void f(int a);` | "expected ')'" |
| `_Noreturn void f(int a);` | "missing closing parenthesis" |
| `E void f(int); E int v;` with `E` a macro collection cannot see | status 0, but the keys are `( void )` and `( int )`, not `( f )` and `( v )` |
| `extern "C" {` / `#include "inner.h"` / `}` with no `__cplusplus` guard | "missing '}'": each include-delimited segment checks its braces alone |

Two of the forms also fail in unit source, which is a defect independent of
collection: `_Noreturn void die(int a) { exit(a); }` reports "missing closing
parenthesis", and a leading `__attribute__((visibility("default")))` on a
definition reports "expected ')'". A trailing attribute is accepted in both
places, as the corpus plan decided.

## Decisions needed

- Whether a function-like attribute macro before the type is skipped by
  name when every definition expands to nothing or to `__attribute__((...))`,
  or through host preprocessing for collection only.
- What collection records for a prefix name with no visible definition.

## Implementation outline

- Extend the `<empty>` and attribute facts recorded in `_note_object_macro`
  (`src/compiler.x`) to function-like macros, and skip an invocation with its
  balanced argument list where `_skip_empty_macro` (`src/parse.x`) already
  skips a name.
- Accept a leading `__attribute__((...))` and `_Noreturn` among declaration
  specifiers, in units and collected headers alike, carrying the spelling for
  emission the way a trailing attribute is carried.
- For the unguarded linkage group, let a segment end inside a group opened by
  `Compiler.skip_linkage_brace` and close it in a later segment of the same
  file. The corpus plan dropped this because hiding the C++ arm made the
  guarded form pass; only the unguarded form needs it.

## Validation

- A compiler fixture per form in the style of `c-annotation-macro` and
  `c-linkage-include`, whose header uses the form and whose unit calls the
  declarations, plus unit-source fixtures for `_Noreturn` and a leading
  attribute.
- `make -C packages/libcurl test run run-lisp` with `-I` added for its
  upstream headers.

## Plan review

- Facts: `_note_object_macro` already records each definition from the
  source; the new skips consume only names and invocations whose recorded
  definitions contribute no declaration syntax, and nothing rechecks them.
- Reuse: extends the existing macro map, `_skip_empty_macro`, the trailing
  attribute carrier, and `Compiler.skip_linkage_brace`; no new traversal or
  cache.
- Idiom: a direct parser skip over recorded facts, not a preprocessor.
- Validators and diagnostics: none proposed.
