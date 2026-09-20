# Header collection gaps

> Status: needs author scoping - 2026-09-16, rows re-reproduced 2026-09-17.
> Found while repairing raylib collection in PR #62. The corpus work in
> `plans/archive/x2c-c-on-ramp-corpus.md` (f6f029f) fixed the empty and
> storage-class prefix macros, macros among parameters, and the
> `__cplusplus`-guarded linkage group. On 2026-09-17 the syntax cleanup made
> the attribute macro invocation and the `_Noreturn` row parse in headers and
> units alike (fixtures `c-annotation-macro`, `c-trailing-attribute`, and
> `native-noreturn`). The leading `__attribute__` row turned out to be the
> repository review's Group 1 miscompile, fixed separately in `1956007c` by
> keeping a leading attribute out of the declared and bound types
> (fixture `leading-attribute-types`). The two remaining rows still fail.
> No package build hits them today.

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
| `#define ATTR(x)` or `#define ATTR(x) __attribute__((deprecated))`, then `ATTR(1) void f(int a);`, as libcurl's `CURL_DEPRECATED(...)` at `curl.h:157` | fixed 2026-09-17 |
| `__attribute__((visibility("default"))) void f(int a);` | fixed 2026-09-17 in `1956007c` |
| `_Noreturn void f(int a);` | fixed 2026-09-17 |
| `E void f(int); E int v;` with `E` a macro collection cannot see | status 0, but the keys are `( void )` and `( int )`, not `( f )` and `( v )` |
| `extern "C" {` / `#include "inner.h"` / `}` with no `__cplusplus` guard | "missing '}'": each include-delimited segment checks its braces alone |

A leading attribute or `_Noreturn` is kept in the declaration's specifiers
as source text, which the type ignores; a trailing attribute stays with its
declarator, as the corpus plan decided.

## Making a real third-party header visible

Member access reaches a native struct with `.` whenever x2c parsed the
declaration: verified 2026-09-17 against a local header and against the real
`termbox2.h`, where `struct tb_event *event; event.type` compiles and runs.
The reason package sources still write `->` on ~190 handle members is not the
language but the wiring: a pinned shim such as `packages/libuv/src/uv-152.h`
is thirteen lines around `#include <uv.h>`, which only the C compiler
resolves, so x2c never sees the layout and emits `.` verbatim into C.

Two gaps block closing that, both reproduced at ecdcea9:

- Collection reads `#include` directives inside conditional branches that are
  false. A header with `#if defined(X2C_NEVER_DEFINED_MACRO)` around
  `#include "never.h"` fails on the contents of `never.h`, which is why
  pointing x2c at the installed `uv.h` dies inside `uv/win.h` behind
  `#if defined(_WIN32)`.
- A struct body far from its forward typedef does not resolve. With the real
  `yyjson.h` on the include path, `yyjson_read_err *e; e.code` works (the
  type is defined at line 886) while `yyjson_doc *d; d.read_size` still emits
  `.`; that struct's forward typedef is at line 693 and its body at 4770, with
  41 conditionals between them. A minimal forward-typedef-then-body header
  resolves, so the trigger is not the shape alone and is not isolated.

Closing both would let packages put their pinned headers on x2c's read path
and delete those arrows, and it is a prerequisite for any `sizeof` or field
access against an upstream C type. Until then, `->` on a native handle is
correct and the style guide says so. The dogfooding campaign therefore
excludes those sites; see
[x2c-dogfooding-remediation](archive/x2c-dogfooding-remediation.md).

## Decisions needed

- What collection records for a prefix name with no visible definition.

## Implementation outline

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
- Reuse: extends the existing `object_macros` map and its `<annotation>` and
  `<wrapper>` markers (`src/compiler.x:1493`), the prefix-word scan
  (`src/parse.x:272`), the trailing attribute carrier, and
  `Compiler.skip_linkage_brace`; no new traversal or cache.
- Idiom: a direct parser skip over recorded facts, not a preprocessor.
- Validators and diagnostics: none proposed.
